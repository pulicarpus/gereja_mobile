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
    throw std::runtime_error(std::string("SDK operation failed: ") +
      (future.error_message() ? future.error_message() : "unknown"));
  }
}

int main(int argc, char** argv) {
  try {
    std::cout << "Phase: create local app" << std::endl;
    firebase::AppOptions options;
    options.set_project_id("gkii-local-regression");
    options.set_app_id("1:123456789:windows:local-regression");
    options.set_api_key("local-regression-unused-api-key");
    auto* app = firebase::App::Create(options, "gkii-settings-test");
    if (!app) throw std::runtime_error("App initialization failed");
    std::cout << "Phase: get Firestore instance" << std::endl;
    auto* db = firebase::firestore::Firestore::GetInstance(app);
    // No production project, authentication or uploads. Restrict the SDK to a
    // closed loopback port and disable persistence and network before testing.
    auto settings = db->settings();
    settings.set_host("127.0.0.1:1");
    settings.set_ssl_enabled(false);
    settings.set_persistence_enabled(false);
    std::cout << "Phase: apply initial settings" << std::endl;
    gkii_apply_firestore_settings(db, settings);
    if (db->settings() != settings) throw std::runtime_error("Initial settings not applied");
    std::cout << "Phase: disable network and start client" << std::endl;
    wait_for(db->DisableNetwork());
    const std::string mode = argc > 1 ? argv[1] : "--guarded";
    // The prebuilt SDK exception can escape this executable's C++ handlers.
    // Run deliberate failures in child processes and check their exact Windows
    // exception exit code in the regression driver instead of crashing the
    // guarded case before it can execute.
    if (mode == "--unsafe-settings") {
      std::cout << "Phase: reproduce original exception" << std::endl;
      db->set_settings(settings);
      throw std::runtime_error("Original SDK assignment unexpectedly succeeded");
    }
    if (mode == "--late-change") {
      std::cout << "Phase: reject changed settings" << std::endl;
      auto different = settings;
      different.set_host("127.0.0.1:2");
      gkii_apply_firestore_settings(db, different);
      throw std::runtime_error("Late settings change unexpectedly succeeded");
    }
    if (mode != "--guarded") throw std::runtime_error("Unknown test mode");
    std::cout << "Phase: verify identical settings guard" << std::endl;
    for (int i = 0; i < 10; ++i) gkii_apply_firestore_settings(db, settings);
    if (db->settings() != settings) throw std::runtime_error("Guard changed settings");
    std::cout << "Phase: terminate local client" << std::endl;
    wait_for(db->Terminate());
    delete db;
    delete app;
    std::cout << "Repeated identical settings passed without native exception\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
