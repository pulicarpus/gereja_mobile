import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

// Fungsi merapikan format ayat (contoh: 1,2,3 -> 1-3)
String formatNasRange(String rawNas) {
  try {
    if (!rawNas.contains(":")) return rawNas;
    List<String> parts = rawNas.split(":");
    String head = parts[0];
    List<int> verses = parts[1].split(",").map((e) => int.parse(e.trim())).toList();
    if (verses.length <= 1) return rawNas;
    
    verses.sort();
    bool isConsecutive = true;
    for (int i = 0; i < verses.length - 1; i++) {
      if (verses[i + 1] != verses[i] + 1) {
        isConsecutive = false;
        break;
      }
    }
    
    return isConsecutive ? "$head:${verses.first}-${verses.last}" : rawNas;
  } catch (e) {
    return rawNas;
  }
}

class NoteDetailsPage extends StatefulWidget {
  final String nas;
  final String rawNas;
  final String? existingKey;
  final SharedPreferences prefs;
  final Database db;
  final List<Map<String, dynamic>> allBooks;
  final Function(String) onJumpToBible;

  const NoteDetailsPage({
    super.key,
    required this.nas,
    required this.rawNas,
    this.existingKey,
    required this.prefs,
    required this.db,
    required this.allBooks,
    required this.onJumpToBible,
  });

  @override
  State<NoteDetailsPage> createState() => _NoteDetailsPageState();
}

class _NoteDetailsPageState extends State<NoteDetailsPage> {
  String title = "Tanpa Judul", content = "", displayNas = "";

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    displayNas = widget.nas;
    if (widget.existingKey != null) {
      String? data = widget.prefs.getString(widget.existingKey!);
      if (data != null && data.contains("~|~")) {
        List<String> p = data.split("~|~");
        displayNas = formatNasRange(p[0]);
        title = p[1].isEmpty ? "Tanpa Judul" : p[1];
        content = p[5];
      }
    }
  }

  void _showFloatingVerse(String ref) async {
    try {
      final regex = RegExp(r'([1-3]?\s?[A-Za-z]+)\s(\d+):(\d+)(-\d+)?');
      final match = regex.firstMatch(ref);
      if (match == null) return;

      String kitab = match.group(1)!;
      int pasal = int.parse(match.group(2)!);
      String ayatPart = match.group(3)!;
      List<int> ayatRange = [];

      if (match.group(4) != null) {
        int start = int.parse(ayatPart);
        int end = int.parse(match.group(4)!.replaceAll("-", ""));
        for (int i = start; i <= end; i++) ayatRange.add(i);
      } else {
        ayatRange.add(int.parse(ayatPart));
      }

      int bId = widget.allBooks.firstWhere(
          (b) => b['name'].toString().toLowerCase() == kitab.toLowerCase())['_id'];

      // Query disesuaikan: book_id dan content
      final data = await widget.db.query('verses',
          where: 'book_id = ? AND chapter = ? AND verse IN (${ayatRange.join(",")})',
          whereArgs: [bId, pasal]);

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (c) => Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(ref, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Divider(),
            Flexible(
                child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: data.length,
                    itemBuilder: (cc, idx) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Text("${data[idx]['verse']}. ${data[idx]['content']}"),
                        ))),
            ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                  widget.onJumpToBible(ref);
                },
                child: const Text("Buka di Alkitab")),
          ]),
        ),
      );
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Isi Catatan")),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(displayNas, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Divider(),
            const SizedBox(height: 10),
            Text(content, style: const TextStyle(fontSize: 18)),
          ])),
    );
  }
}

// Tambahkan kelas NoteEditorPage dan NoteListPage (sama seperti sebelumnya tapi gunakan formatNasRange)
class NoteListPage extends StatefulWidget {
  final SharedPreferences prefs;
  final Database db;
  final List<Map<String, dynamic>> allBooks;
  final Function(String) onOpenNote;

  const NoteListPage({super.key, required this.prefs, required this.db, required this.allBooks, required this.onOpenNote});

  @override
  State<NoteListPage> createState() => _NoteListPageState();
}

class _NoteListPageState extends State<NoteListPage> {
  @override
  Widget build(BuildContext context) {
    List<String> keys = (widget.prefs.getStringList("ALL_NOTE_KEYS") ?? []).reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text("Daftar Catatan")),
      body: ListView.builder(
        itemCount: keys.length,
        itemBuilder: (context, i) {
          String? raw = widget.prefs.getString(keys[i]);
          if (raw == null) return const SizedBox();
          List<String> p = raw.split("~|~");
          return ListTile(
            title: Text(p[1].isEmpty ? "Tanpa Judul" : p[1]),
            subtitle: Text(formatNasRange(p[0])),
            onTap: () => widget.onOpenNote(keys[i]),
          );
        },
      ),
    );
  }
}