import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'desktop_session.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'windows_firebase_options.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

void startupCheckpoint(String label) {
  if (!Platform.isWindows) return;
  final trace = Platform.environment['GKII_STARTUP_TRACE_PATH'];
  if (trace == null || trace.isEmpty) return;
  try { File(trace).writeAsStringSync('dart: $label\n', mode: FileMode.append); }
  catch (_) { /* Diagnostics must not affect startup. */ }
}

Future<void> initializeAppServices() async {
  if (Platform.isWindows) {
    startupCheckpoint('initialize SQLite');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    startupCheckpoint('application support directory');
    final support = await getApplicationSupportDirectory();
    await databaseFactory.setDatabasesPath(path.join(support.path, 'bible'));
    startupCheckpoint('initialize Firebase');
    await Firebase.initializeApp(options: windowsFirebaseOptions);
    // Initialize auth before splash routing can mistake its empty Dart snapshot
    // for a signed-out session. Native Firebase persists credentials securely.
    startupCheckpoint('wait for desktop auth session');
    await waitForDesktopSession(FirebaseAuth.instance.authStateChanges());
    startupCheckpoint('services initialized');
  } else {
    await Firebase.initializeApp();
  }
}
