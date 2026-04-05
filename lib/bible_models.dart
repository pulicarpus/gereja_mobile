class BibleBook {
  final int id;
  final String name;
  BibleBook({required this.id, required this.name});
}

class NoteModel {
  final String key;
  final String nas;
  final String title;
  final String date;
  final String content;
  final String rawData; // Data asli format ~|~

  NoteModel({
    required this.key,
    required this.nas,
    required this.title,
    required this.date,
    required this.content,
    required this.rawData,
  });

  // Fungsi untuk memecah string ~|~ ala Kotlin bos
  factory NoteModel.fromRaw(String key, String raw) {
    List<String> p = raw.split("~|~");
    return NoteModel(
      key: key,
      nas: p.isNotEmpty ? p[0] : "",
      title: p.length > 1 ? (p[1].isEmpty ? "Tanpa Judul" : p[1]) : "Tanpa Judul",
      date: p.length > 3 ? p[3] : "",
      content: p.length > 5 ? p[5] : "",
      rawData: raw,
    );
  }
}