#include "firestore_settings_guard.h"
#include "firebase/app.h"
#include "firebase/firestore.h"
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <thread>

void wait_for(const firebase::Future<void>& future) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(20);
  while (future.status() == firebase::kFutureStatusPending) {
    if (std::chrono::steady_clock::now() > deadline) throw std::runtime_error("SDK timed out");
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  if (future.status() != firebase::kFutureStatusComplete || future.error() != 0) {
    throw std::runtime_error("SDK operation failed");
  }
}

int main() {
  try {
    firebase::AppOptions options;
    options.set_project_id("gkii-local-regression");
    options.set_app_id("1:123456789:windows:local-regression");
    options.set_api_key("local-regression-unused-api-key");
    auto* app = firebase::App::Create(options, "gkii-settings-test");
    if (!app) throw std::runtime_error("App initialization failed");
    auto* db = firebase::firestore::Firestore::GetInstance(app);
    // No production project, authentication or uploads. Restrict the SDK to a
    // closed loopback port and disable persistence and network before testing.
    auto settings = db->settings();
    settings.set_host("127.0.0.1:1");
    settings.set_ssl_enabled(false);
    settings.set_persistence_enabled(false);
    gkii_apply_firestore_settings(db, settings);
    if (db->settings() != settings) throw std::runtime_error("Initial settings not applied");
    wait_for(db->DisableNetwork());
    bool reproduced = false;
    try { db->set_settings(settings); }
    catch (const std::logic_error&) { reproduced = true; }
    if (!reproduced) throw std::runtime_error("Expected SDK exception was not reproduced");
    for (int i = 0; i < 10; ++i) gkii_apply_firestore_settings(db, settings);
    auto different = settings;
    different.set_host("127.0.0.1:2");
    bool rejected = false;
    try { gkii_apply_firestore_settings(db, different); }
    catch (const std::logic_error&) { rejected = true; }
    if (!rejected || db->settings() != settings) {
      throw std::runtime_error("Guard allowed late configuration changes");
    }
    wait_for(db->Terminate());
    delete db;
    delete app;
    std::cout << "Reproduced SDK exception; repeated identical settings passed; late changes rejected\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
