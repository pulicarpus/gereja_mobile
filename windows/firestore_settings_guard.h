#pragma once
#include <string>

inline std::string gkii_firestore_database_id(const std::string& database) {
  return database.empty() ? "(default)" : database;
}

inline std::string gkii_firestore_cache_key(const std::string& app,
                                          const std::string& database) {
  return app + "-" + gkii_firestore_database_id(database);
}

// Firebase C++ rejects every settings assignment after its client starts,
// including assignments of identical settings. FlutterFire can encounter an
// existing SDK instance while populating its own instance cache.
template <typename Firestore, typename Settings>
void gkii_apply_firestore_settings(Firestore* firestore,
                                   const Settings& settings) {
  if (firestore->settings() != settings) {
    firestore->set_settings(settings);
  }
}
