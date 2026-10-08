import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DictionaryEntry {
  final String term, definition, source;
  final List<String> references;
  DictionaryEntry({
    required this.term,
    required this.definition,
    required this.source,
    required this.references,
  });
  factory DictionaryEntry.fromRow(Map<String, Object?> row) => DictionaryEntry(
    term: row['term'] as String,
    definition: row['definition'] as String,
    source: row['source'] as String,
    references: (jsonDecode(row['refs'] as String) as List).cast<String>(),
  );
}

class DictionaryStore {
  final Database db;
  DictionaryStore(this.db);
  static Future<DictionaryStore>? _shared;
  static Future<DictionaryStore> open() =>
      _shared ??= _open().catchError((Object error) {
        _shared = null;
        throw error;
      });
  static const developmentPath = String.fromEnvironment('DICTIONARY_PATH');
  static Future<DictionaryStore> _open() async {
    if (developmentPath.isNotEmpty) {
      return DictionaryStore(
        await openDatabase(developmentPath, readOnly: true),
      );
    }
    final data = await rootBundle.load('assets/dictionary/offline.sqlite');
    final folder = await getDatabasesPath();
    await Directory(folder).create(recursive: true);
    final file = File(p.join(folder, 'dictionary-offline.sqlite'));
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
    return DictionaryStore(await openDatabase(file.path, readOnly: true));
  }

  Future<List<DictionaryEntry>> search(String query) async {
    final keyword = query.trim().toLowerCase();
    final escaped = keyword
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final rows = await db.rawQuery(
      "SELECT * FROM entries WHERE search_term LIKE ? ESCAPE '\\' ORDER BY CASE WHEN search_term = ? THEN 0 ELSE 1 END, search_term, id LIMIT 100",
      ['$escaped%', keyword],
    );
    return rows.map(DictionaryEntry.fromRow).toList();
  }
}
