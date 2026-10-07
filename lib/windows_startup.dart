import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'windows_firebase_options.dart';

Future<void> initializeAppServices() async {
  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await Firebase.initializeApp(options: windowsFirebaseOptions);
  } else {
    await Firebase.initializeApp();
  }
}
