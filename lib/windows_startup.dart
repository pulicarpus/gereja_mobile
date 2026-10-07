import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
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
    await setDatabasesPath(path.join(support.path, 'bible'));
    await Firebase.initializeApp(options: windowsFirebaseOptions);
  } else {
    await Firebase.initializeApp();
  }
}
