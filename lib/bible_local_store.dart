import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'bible_models.dart';

// Hanya penyimpanan perangkat. Koleksi dan format backup Firebase tetap sama.
class BibleLocalStore {
  final SharedPreferences prefs;
  final String? uid;
  BibleLocalStore(this.prefs, this.uid);

  String get _prefix => 'BIBLE_V2_${uid == null ? "guest" : "user_$uid"}_';
  String _key(String name) => '$_prefix$name';
  List<String> get noteKeys => prefs.getStringList(_key('notes')) ?? [];
  Set<String> get deletedKeys =>
      (prefs.getStringList(_key('deleted')) ?? []).toSet();
  String? readNote(String key) => prefs.getString(_key('note_$key'));
  bool get hasLegacyNotes =>
      (prefs.getStringList('ALL_NOTE_KEYS') ?? []).isNotEmpty ||
      prefs.getString('BIBLE_HIGHLIGHTS') != null;

  Future<void> saveNote(String key, String value) async {
    await prefs.setString(_key('note_$key'), value);
    final keys = noteKeys;
    if (!keys.contains(key)) keys.add(key);
    await prefs.setStringList(_key('notes'), keys);
    final deleted = deletedKeys..remove(key);
    await prefs.setStringList(_key('deleted'), deleted.toList());
  }

  Future<void> deleteNote(String key) async {
    final deleted = deletedKeys..add(key);
    await prefs.setStringList(_key('deleted'), deleted.toList());
    await prefs.setStringList(_key('notes'), noteKeys..remove(key));
    await prefs.remove(_key('note_$key'));
  }

  // Tidak mengasumsikan catatan lama milik akun yang sedang masuk.
  // Dipanggil hanya setelah pengguna memilih impor dan mengonfirmasi kepemilikan.
  Future<int> importLegacyNotes() async {
    var count = 0;
    for (final key in prefs.getStringList('ALL_NOTE_KEYS') ?? <String>[]) {
      final raw = prefs.getString(key);
      if (raw == null || deletedKeys.contains(key) || readNote(key) != null)
        continue;
      final note = NoteModel.fromRaw(key, raw);
      await saveNote(key, note.toLocalJson());
      count++;
    }
    return count;
  }

  Map<String, dynamic> loadHighlights() {
    try {
      final decoded = jsonDecode(prefs.getString(_key('highlights')) ?? '{}');
      if (decoded is! Map<String, dynamic>) return {};
      return Map.fromEntries(
        decoded.entries.where(
          (entry) =>
              entry.value is Map &&
              entry.value['color'] is int &&
              (entry.value['label'] == null || entry.value['label'] is String),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> saveHighlights(Map<String, dynamic> highlights) =>
      prefs.setString(_key('highlights'), jsonEncode(highlights)).then((_) {});

  Future<void> importLegacyHighlights() async {
    try {
      final old = jsonDecode(prefs.getString('BIBLE_HIGHLIGHTS') ?? '{}');
      if (old is Map<String, dynamic>) {
        final merged = {...old, ...loadHighlights()};
        await saveHighlights(merged);
      }
    } catch (_) {
      /* Sumber lama tetap tersimpan meski rusak. */
    }
  }
}
