#pragma once

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
