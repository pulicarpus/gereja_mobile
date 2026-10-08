import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'desktop_session.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'windows_firebase_options.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

Future<void> initializeAppServices() async {
  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final support = await getApplicationSupportDirectory();
    await databaseFactory.setDatabasesPath(path.join(support.path, 'bible'));
    await Firebase.initializeApp(options: windowsFirebaseOptions);
    // Initialize auth before splash routing can mistake its empty Dart snapshot
    // for a signed-out session. Native Firebase persists credentials securely.
    await waitForDesktopSession(FirebaseAuth.instance.authStateChanges());
  } else {
    await Firebase.initializeApp();
  }
}
