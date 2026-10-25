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
    final structured = tryStructured(key, raw);
    if (structured != null) return structured;
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

  static NoteModel? tryStructured(String key, String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is! Map ||
          !['bible-note-v2', 'bible-note-v3'].contains(data['format']) ||
          data['nas'] is! String ||
          data['title'] is! String ||
          data['date'] is! String ||
          data['content'] is! String ||
          (data['preacher'] != null && data['preacher'] is! String))
        return null;
      return NoteModel(
        key: key,
        nas: data['nas'],
        title: data['title'],
        preacher: data['preacher'] ?? '',
        date: data['date'],
        content: data['content'],
        richDelta: validTextDelta(data['richDelta']),
        rawData: raw,
      );
    } catch (_) {
      return null;
    }
  }

  // The editor currently supports text formatting, not embedded media.
  static List<dynamic>? validTextDelta(Object? value) {
    if (value is! List || value.isEmpty) return null;
    for (final operation in value) {
      if (operation is! Map ||
          operation['insert'] is! String ||
          operation.keys.any((key) => key != 'insert' && key != 'attributes'))
        return null;
      final attrs = operation['attributes'];
      if (attrs != null &&
          (attrs is! Map ||
              attrs.keys.any((k) => k is! String) ||
              attrs.values.any(
                (v) => v != null && v is! String && v is! num && v is! bool,
              )))
        return null;
    }
    if (!(value.last['insert'] as String).endsWith('\n')) return null;
    return List<dynamic>.from(value);
  }

  static String backupPayload(String key, Map<String, dynamic> data) {
    final structured = data['structured_data'];
    if (structured is String && tryStructured(key, structured) != null)
      return structured;
    return data['raw_data'] is String ? data['raw_data'] as String : '';
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
