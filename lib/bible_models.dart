import 'dart:convert';

class BibleBook {
  final int bookNumber;
  final String name;
  final String shortName;
  BibleBook({
    required this.bookNumber,
    required String name,
    required String shortName,
  }) : name = name.trim(),
       shortName = shortName.trim();
}

class NoteModel {
  final String key, nas, title, date, content, rawData, preacher;
  // Quill Delta ops. Null means a legacy plain-text note.
  final List<dynamic>? richDelta;
  NoteModel({
    required this.key,
    required this.nas,
    required this.title,
    required this.date,
    required this.content,
    required this.rawData,
    this.preacher = '',
    this.richDelta,
  });

  factory NoteModel.fromRaw(String key, String raw) {
    if (raw.startsWith('{')) {
      try {
        final data = jsonDecode(raw);
        if (data is Map &&
            (data['format'] == 'bible-note-v2' ||
                data['format'] == 'bible-note-v3')) {
          return NoteModel(
            key: key,
            nas: data['nas'] as String,
            title: data['title'] as String,
            preacher: data['preacher'] as String,
            date: data['date'] as String,
            content: data['content'] as String,
            rawData: raw,
            richDelta: data['richDelta'] is List
                ? List<dynamic>.from(data['richDelta'] as List)
                : null,
          );
        }
      } catch (_) {
        /* Baca format lama jika bukan JSON catatan valid. */
      }
    }
    final parts = raw.split('~|~');
    return NoteModel(
      key: key,
      nas: parts.first,
      title: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : 'Tanpa Judul',
      preacher: parts.length > 2 ? parts[2] : '',
      date: parts.length > 3 ? parts[3] : '',
      content: parts.length > 5 ? parts.sublist(5).join('~|~') : '',
      rawData: raw,
    );
  }

  String toLocalJson() => jsonEncode({
    'format': richDelta == null ? 'bible-note-v2' : 'bible-note-v3',
    'nas': nas,
    'title': title,
    'preacher': preacher,
    'date': date,
    'content': content,
    if (richDelta != null) 'richDelta': richDelta,
  });

  // Kontrak raw_data cloud tetap dapat dibaca APK lama.
  String toLegacyRaw() => '$nas~|~$title~|~$preacher~|~$date~|~ ~|~$content';
}
