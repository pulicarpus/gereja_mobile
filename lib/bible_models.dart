class BibleBook {
  final int bookNumber;
  final String name;
  final String shortName; // Tambahkan ini

  BibleBook({
    required this.bookNumber, 
    required this.name, 
    required this.shortName
  });
}

class NoteModel {
  final String key;
  final String nas;
  final String title;
  final String date;
  final String content;
  final String rawData;

  NoteModel({
    required this.key,
    required this.nas,
    required this.title,
    required this.date,
    required this.content,
    required this.rawData,
  });

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