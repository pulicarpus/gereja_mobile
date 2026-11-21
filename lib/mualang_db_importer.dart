import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Imports user-provided Mualang SQLite, without shipping scripture in GitHub.
/// The user must obtain MUALANG.SQLite3 separately and select it once.
class MualangDbImporter {
  static const fileName = 'MUALANG.SQLite3';

  static Future<String> _destination() async =>
      p.join(await getDatabasesPath(), fileName);

  static Future<bool> isInstalled() async =>
      databaseExists(await _destination());

  static Future<bool> importFromPicker() async {
    if (await isInstalled()) return true;

    // FileType.any supports database files chosen from Android's document picker
    // without needing broad storage permissions.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any, allowMultiple: false, withData: false);
    if (result == null) return false;

    final path = result.files.single.path;
    if (path == null) {
      throw StateError('Berkas tidak tersedia dari pemilih file');
    }

    final targetPath = await _destination();
    final temp = File('$targetPath.importing');
    await temp.parent.create(recursive: true);
    if (await temp.exists()) await temp.delete();

    Database? db;
    try {
      await File(path).copy(temp.path);
      db = await openDatabase(temp.path, readOnly: true);
      final check = await db.rawQuery('PRAGMA quick_check');
      if (check.isEmpty || check.first.values.first.toString().toLowerCase() != 'ok') {
        throw const FormatException('Integritas SQLite tidak valid');
      }
      final books = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM books')) ?? 0;
      final verses = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM verses')) ?? 0;
      final source = await db.rawQuery(
          "SELECT value FROM mualang_source_info WHERE key = 'label'");
      if (books != 25 || verses < 7000 || source.isEmpty ||
          source.first['value'] != 'Perjanjian Baru Mualang') {
        throw const FormatException('File bukan database PB Mualang yang disiapkan');
      }
      await db.close();
      db = null;
      await temp.rename(targetPath);
      return true;
    } finally {
      await db?.close();
      if (await temp.exists()) await temp.delete();
    }
  }
}
