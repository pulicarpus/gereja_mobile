import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "firestore_patch", Path(__file__).parents[2] / "tool/patch_windows_firestore.py")
patcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patcher)


class FirestorePatchTests(unittest.TestCase):
    def test_codec_uses_database_cache_before_settings_and_one_owner(self):
        source = '''if (CloudFirestorePlugin::firestoreInstances_.find(appName) != end) {
          return CloudFirestorePlugin::firestoreInstances_[appName].get();
        }
        Firestore* firestore = Firestore::GetInstance(app);
        firestore->set_settings(settings);
        CloudFirestorePlugin::firestoreInstances_[appName] = owner;
        '''
        result = patcher.patch("firestore_codec.cpp", source)
        self.assertIn("gkii_firestore_cache_key(appName, databaseUrl)", result)
        self.assertNotIn("firestoreInstances_[appName]", result)
        self.assertIn("gkii_firestore_database_id(databaseUrl).c_str()", result)
        self.assertLess(result.index("return CloudFirestorePlugin"),
                        result.index("gkii_apply_firestore_settings"))

    def test_pigeon_uses_same_key(self):
        result = patcher.patch("cloud_firestore_plugin.cpp",
            'pigeonApp.app_name() + "-" + pigeonApp.database_u_r_l();\n'
            'Firestore::GetInstance(app, pigeonApp.database_u_r_l().c_str());\n'
            'firestore->set_settings(settings);')
        self.assertIn("gkii_firestore_cache_key(pigeonApp.app_name(), pigeonApp.database_u_r_l())", result)
        self.assertNotIn("firestore->set_settings", result)

    def test_upstream_changes_fail_closed(self):
        with self.assertRaises(ValueError):
            patcher.patch("firestore_codec.cpp", "unexpected source")


if __name__ == '__main__':
    unittest.main()
