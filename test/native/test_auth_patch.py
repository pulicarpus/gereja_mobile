import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('auth_patch', ROOT / 'tool/patch_windows_auth.py')
auth_patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth_patch)

class AuthPatchTest(unittest.TestCase):
    def source(self):
        return '\n'.join('''class %s : public Listener {
  void callback() {
    firebase::auth::User user = auth->current_user();
    PigeonUserDetails userDetails = FirebaseAuthPlugin::ParseUserDetails(user);
    if (event_sink_) {
      if (user.is_valid()) {
        send(userDetails);
      } else {
        send_null();
      }
    }
  }
 private:
  Sink sink;
};''' % name for name in ('FlutterIdTokenListener', 'FlutterAuthStateListener'))

    def test_both_listeners_keep_signed_out_events_and_gate_metadata(self):
        patched = auth_patch.patch(self.source())
        self.assertEqual(patched.count('send_null();'), 2)
        self.assertEqual(patched.count('if (user.is_valid()) {\n        PigeonUserDetails'), 2)
        self.assertEqual(patched.count('send(userDetails);'), 2)

    def test_upstream_change_fails_instead_of_silently_skipping_guard(self):
        with self.assertRaises(ValueError):
            auth_patch.patch(self.source().replace('if (user.is_valid()) {', 'if (changed()) {'))

    def test_double_patch_is_rejected(self):
        with self.assertRaises(ValueError):
            auth_patch.patch(auth_patch.patch(self.source()))
