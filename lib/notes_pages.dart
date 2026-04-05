import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

// Helper: Merapikan tampilan ayat (1,2,3 -> 1-3)
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
      if (verses[i + 1] != verses[i] + 1) { isConsecutive = false; break; }
    }
    return isConsecutive ? "$head:${verses.first}-${verses.last}" : rawNas;
  } catch (e) { return rawNas; }
}

// --- HALAMAN DETAIL ---
class NoteDetailsPage extends StatefulWidget {
  final String nas;
  final String rawNas;
  final String? existingKey;
  final SharedPreferences prefs;
  final Database db;
  final List<Map<String, dynamic>> allBooks;
  final Function(String) onJumpToBible;

  const NoteDetailsPage({
    super.key, required this.nas, required this.rawNas, this.existingKey,
    required this.prefs, required this.db, required this.allBooks, required this.onJumpToBible,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Isi Catatan"), actions: [
        IconButton(icon: const Icon(Icons.edit), onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(
            nas: displayNas, existingKey: widget.existingKey, prefs: widget.prefs,
          ))).then((_) => setState(() => _loadData()));
        })
      ]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(displayNas, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const Divider(),
          const SizedBox(height: 10),
          Text(content, style: const TextStyle(fontSize: 18, height: 1.5)),
        ]),
      ),
    );
  }
}

// --- HALAMAN EDITOR ---
class NoteEditorPage extends StatefulWidget {
  final String nas;
  final String? existingKey;
  final SharedPreferences prefs;
  const NoteEditorPage({super.key, required this.nas, this.existingKey, required this.prefs});

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late TextEditingController _tCtrl, _cCtrl;

  @override
  void initState() {
    super.initState();
    String t = "", c = "";
    if (widget.existingKey != null) {
      String? d = widget.prefs.getString(widget.existingKey!);
      if (d != null && d.contains("~|~")) {
        List<String> p = d.split("~|~");
        t = p[1]; c = p[5];
      }
    }
    _tCtrl = TextEditingController(text: t);
    _cCtrl = TextEditingController(text: c);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Tulis Catatan"), actions: [
        IconButton(icon: const Icon(Icons.save), onPressed: () async {
          String key = widget.existingKey ?? "Note_${DateTime.now().millisecondsSinceEpoch}";
          String data = "${widget.nas}~|~${_tCtrl.text}~|~-~|~${DateTime.now().toString().substring(0, 16)}~|~-~|~${_cCtrl.text}";
          List<String> keys = widget.prefs.getStringList("ALL_NOTE_KEYS") ?? [];
          if (!keys.contains(key)) {
            keys.add(key);
            await widget.prefs.setStringList("ALL_NOTE_KEYS", keys);
          }
          await widget.prefs.setString(key, data);
          if (mounted) Navigator.pop(context);
        })
      ]),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          TextField(controller: _tCtrl, decoration: const InputDecoration(labelText: "Judul")),
          Expanded(child: TextField(controller: _cCtrl, maxLines: null, decoration: const InputDecoration(hintText: "Isi catatan..."))),
        ]),
      ),
    );
  }
}

// --- HALAMAN DAFTAR CATATAN ---
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
      body: keys.isEmpty 
        ? const Center(child: Text("Belum ada catatan"))
        : ListView.builder(
            itemCount: keys.length,
            itemBuilder: (context, i) {
              String? raw = widget.prefs.getString(keys[i]);
              if (raw == null) return const SizedBox();
              List<String> p = raw.split("~|~");
              return ListTile(
                leading: const Icon(Icons.description, color: Colors.indigo),
                title: Text(p[1].isEmpty ? "Tanpa Judul" : p[1], style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("${formatNasRange(p[0])}\n${p[3]}"),
                onTap: () => widget.onOpenNote(keys[i]),
              );
            },
          ),
    );
  }
}