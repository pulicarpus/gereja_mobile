// Exercise the actual FlutterFire codec and Pigeon creation paths, not a mock.
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <vector>
#include "cloud_firestore_plugin.h"
#include "firestore_codec.h"
#include "firestore_settings_guard.h"
#include "firebase/app.h"
#include "firebase/firestore.h"

namespace cloud_firestore_windows {
firebase::firestore::Firestore* GetFirestoreFromPigeon(
    const FirestorePigeonFirebaseApp& app);
}

class Writer : public flutter::ByteStreamWriter {
 public:
  std::vector<uint8_t> bytes;
  void WriteByte(uint8_t value) override { bytes.push_back(value); }
  void WriteBytes(const uint8_t* values, size_t size) override {
    bytes.insert(bytes.end(), values, values + size);
  }
  void WriteAlignment(uint8_t alignment) override {
    while (bytes.size() % alignment) WriteByte(0);
  }
};

void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

void wait_for(const firebase::Future<void>& future) {
  auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(20);
  while (future.status() == firebase::kFutureStatusPending) {
    require(std::chrono::steady_clock::now() < deadline, "SDK timed out");
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  require(future.status() == firebase::kFutureStatusComplete && future.error() == 0,
          "SDK operation failed");
}

flutter::EncodableValue decode(const std::string& app, const std::string& database,
                              bool document) {
  using namespace cloud_firestore_windows;
  Writer writer;
  auto& standard = flutter::StandardCodecSerializer::GetInstance();
  if (document) writer.WriteByte(FirestoreCodec::DATA_TYPE_DOCUMENT_REFERENCE);
  writer.WriteByte(FirestoreCodec::DATA_TYPE_FIRESTORE_INSTANCE);
  standard.WriteValue(flutter::EncodableValue(app), &writer);
  standard.WriteValue(flutter::EncodableValue(database), &writer);
  writer.WriteByte(FirestoreCodec::DATA_TYPE_FIRESTORE_SETTINGS);
  // Deliberately different from the running client's host: a cached instance
  // must be returned before attempting to configure it again.
  standard.WriteValue(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("host"), flutter::EncodableValue("127.0.0.1:2")}}), &writer);
  if (document) standard.WriteValue(flutter::EncodableValue("jemaat/local-test"), &writer);
  auto result = flutter::StandardMessageCodec::GetInstance(&FirestoreCodec::GetInstance())
      .DecodeMessage(writer.bytes.data(), writer.bytes.size());
  require(result != nullptr, "Codec did not decode");
  return *result;
}

int main() {
  using namespace cloud_firestore_windows;
  using firebase::firestore::Firestore;
  try {
    firebase::AppOptions options;
    options.set_project_id("gkii-local-codec-regression");
    options.set_app_id("1:123456789:windows:local-codec");
    options.set_api_key("local-unused-api-key");
    auto* app = firebase::App::Create(options, "gkii-codec-test");
    require(app != nullptr, "App not created");
    PigeonFirebaseSettings settings(false);
    settings.set_host("127.0.0.1:1");
    for (const std::string database : {"(default)", "named-test"}) {
      FirestorePigeonFirebaseApp pigeon(app->name(), settings, database);
      auto* db = GetFirestoreFromPigeon(pigeon);
      wait_for(db->DisableNetwork());
      auto expected = db->settings();
      for (int repeat = 0; repeat < 10; ++repeat) {
        auto value = decode(app->name(), database, false);
        auto* actual = std::any_cast<Firestore*>(std::get<flutter::CustomEncodableValue>(value));
        require(actual == db, "Codec selected another database");
        auto document = decode(app->name(), database, true);
        auto reference = std::any_cast<firebase::firestore::DocumentReference>(
            std::get<flutter::CustomEncodableValue>(document));
        require(reference.firestore() == db && reference.path() == "jemaat/local-test",
                "Document reference selected another database");
      }
      require(db->settings() == expected, "Codec reconfigured running client");
      if (database == "(default)") {
        auto value = decode(app->name(), "", false);
        require(std::any_cast<Firestore*>(std::get<flutter::CustomEncodableValue>(value)) == db,
                "Empty database did not reuse default");
      }
    }
    require(CloudFirestorePlugin::firestoreInstances_.size() == 2,
            "Duplicate ownership/cache entries");
    for (auto& entry : CloudFirestorePlugin::firestoreInstances_) wait_for(entry.second->Terminate());
    CloudFirestorePlugin::firestoreInstances_.clear();
    delete app;
    std::cout << "Actual Pigeon/codec document references reused running default and named clients\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
