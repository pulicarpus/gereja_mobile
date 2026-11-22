import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'bible_translation.dart';

/// Private, device-side import of the user's Mualang New Testament SQLite.
/// Scripture text is not stored in the public GitHub repository or APK.
class MualangDbImporter {
  static const fileName = 'MUALANG.SQLite3';

  static Future<String> _destination() async =>
      p.join(await getDatabasesPath(), fileName);

  static Future<bool> isInstalled() async =>
      databaseExists(await _destination());

  /// Check the exact book/chapter in the imported private SQLite database.
  /// This never modifies the installed file and never triggers a new import.
  static Future<BibleChapterAvailability> chapterAvailability(
      int bookNumber, int chapter) async {
    final destination = await _destination();
    if (!await databaseExists(destination)) {
      return BibleChapterAvailability.missingBook;
    }
    final db = await openDatabase(
        destination, readOnly: true, singleInstance: false);
    try {
      final books = await db.query('books',
        columns: ['book_number'],
        where: 'book_number = ?',
        whereArgs: [bookNumber],
        limit: 1,
      );
      if (books.isEmpty) return BibleChapterAvailability.missingBook;
      final chapters = await db.query('verses',
        columns: ['chapter'],
        where: 'book_number = ? AND chapter = ?',
        whereArgs: [bookNumber, chapter],
        limit: 1,
      );
      return bibleChapterAvailability(
        bookNumber, chapter,
        books.map((b) => b['book_number'] as int),
        chapters.map((row) => row['chapter'] as int),
      );
    } finally {
      await db.close();
    }
  }

  /// Returns false if the user cancels. Validates before installing the file.
  static Future<bool> importFromPicker() async {
    if (await isInstalled()) return true;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );
    if (result == null) return false;
    final selectedPath = result.files.single.path;
    if (selectedPath == null) {
      throw const FileSystemException('File yang dipilih tidak dapat dibaca.');
    }

    final destination = await _destination();
    final incoming = File('$destination.incoming');
    await incoming.parent.create(recursive: true);
    if (await incoming.exists()) await incoming.delete();

    Database? db;
    try {
      await File(selectedPath).copy(incoming.path);
      db = await openDatabase(incoming.path, readOnly: true, singleInstance: false);
      final integrity = await db.rawQuery('PRAGMA quick_check');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        throw const FormatException('File SQLite tidak valid');
      }
      final books = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM books'),
      );
      final verses = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM verses'),
      );
      final meta = await db.rawQuery(
        "SELECT value FROM mualang_source_info WHERE key = 'label'",
      );
      if (books != 25 || verses != 7630 ||
          meta.isEmpty || meta.first['value'] != 'Perjanjian Baru Mualang') {
        throw const FormatException('Ini bukan database PB Mualang yang disiapkan');
      }
      await db.close();
      db = null;
      if (await File(destination).exists()) {
        throw const FileSystemException('Database Mualang sudah terpasang.');
      }
      await incoming.rename(destination);
      return true;
    } finally {
      await db?.close();
      if (await incoming.exists()) await incoming.delete();
    }
  }
}
