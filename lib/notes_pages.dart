import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

// --- HALAMAN DETAIL CATATAN ---
class NoteDetailsPage extends StatefulWidget {
  final String nas;
  final String rawNas;
  final String? existingKey;
  final SharedPreferences prefs;
  final Database db;
  final List<Map<String, String>> bibleMeta;
  final Function(String) onJumpToBible;

  const NoteDetailsPage({
    super.key,
    required this.nas,
    required this.rawNas,
    this.existingKey,
    required this.prefs,
    required this.db,
    required this.bibleMeta,
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
        displayNas = p[0];
        title = p[1].isEmpty ? "Tanpa Judul" : p[1];
        content = p[5];
      }
    }
  }

  List<TextSpan> _getParsedContent(String text) {
    List<TextSpan> spans = [];
    final regex = RegExp(r'([1-3]?\s?[A-Za-z]+)\s(\d+):(\d+)(-\d+)?');
    int lastIndex = 0;

    for (var match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }
      String fullMatch = match.group(0)!;
      spans.add(TextSpan(
        text: fullMatch,
        style: const TextStyle(
            color: Colors.blue,
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()
          ..onTap = () => _showFloatingVerse(fullMatch),
      ));
      lastIndex = match.end;
    }
    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex)));
    }
    return spans;
  }

  void _showFloatingVerse(String ref) async {
    try {
      final parts = ref.split(" ");
      String kitab = parts.length > 2 ? "${parts[0]} ${parts[1]}" : parts[0];
      final cv = parts.last.split(":");
      int pasal = int.parse(cv[0]);
      List<int> ayatRange = [];
      if (cv[1].contains("-")) {
        var r = cv[1].split("-");
        for (int i = int.parse(r[0]); i <= int.parse(r[1]); i++) {
          ayatRange.add(i);
        }
      } else {
        ayatRange.add(int.parse(cv[1]));
      }

      int bIdx = widget.bibleMeta
          .indexWhere((m) => m['full']!.toLowerCase() == kitab.toLowerCase());
      if (bIdx == -1) return;
      int bNum = bIdx + 1;

      final data = await widget.db.query('verses',
          where:
              'book_number = ? AND chapter = ? AND verse IN (${ayatRange.join(",")})',
          whereArgs: [bNum, pasal]);

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (c) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(ref,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.indigo)),
              const Divider(),
              Flexible(
                  child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: data.length,
                      itemBuilder: (cc, idx) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Text(
                                "${data[idx]['verse']}. ${data[idx]['text'].toString().replaceAll(RegExp(r'<[^>]*>'), '')}"),
                          ))),
              const SizedBox(height: 10),
              ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                    widget.onJumpToBible(ref);
                  },
                  child: const Text("Buka di Alkitab")),
            ])),
      );
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Isi Catatan"), actions: [
        IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (c) => NoteEditorPage(
                              nas: displayNas,
                              existingKey: widget.existingKey,
                              prefs: widget.prefs,
                            ))).then((_) {
                  setState(() {
                    _loadData();
                  });
                }))
      ]),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: () {
                Navigator.pop(context);
                widget.onJumpToBible(displayNas);
              },
              child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.indigo[50],
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(displayNas,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.indigo))),
            ),
            const SizedBox(height: 15),
            Text(title,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Divider(),
            const SizedBox(height: 10),
            RichText(
                text: TextSpan(
                    style: const TextStyle(
                        fontSize: 18, height: 1.5, color: Colors.black),
                    children: _getParsedContent(content))),
          ])),
    );
  }
}

// --- HALAMAN EDITOR CATATAN ---
class NoteEditorPage extends StatefulWidget {
  final String nas;
  final String? existingKey;
  final SharedPreferences prefs;
  const NoteEditorPage(
      {super.key, required this.nas, this.existingKey, required this.prefs});
  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late TextEditingController _titleCtrl, _contentCtrl;
  @override
  void initState() {
    super.initState();
    String t = "", c = "";
    if (widget.existingKey != null) {
      String? data = widget.prefs.getString(widget.existingKey!);
      if (data != null && data.contains("~|~")) {
        List<String> p = data.split("~|~");
        t = p[1];
        c = p[5];
      }
    }
    _titleCtrl = TextEditingController(text: t);
    _contentCtrl = TextEditingController(text: c);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Catatan"), actions: [
        IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              String key = widget.existingKey ??
                  "Note_${DateTime.now().millisecondsSinceEpoch}";
              String data =
                  "${widget.nas}~|~${_titleCtrl.text}~|~-~|~${DateTime.now().toString().substring(0, 16)}~|~-~|~${_contentCtrl.text}";
              List<String> keys =
                  widget.prefs.getStringList("ALL_NOTE_KEYS") ?? [];
              if (!keys.contains(key)) {
                keys.add(key);
                await widget.prefs.setStringList("ALL_NOTE_KEYS", keys);
              }
              await widget.prefs.setString(key, data);
              if (!mounted) return;
              Navigator.pop(context);
            })
      ]),
      body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: "Judul Khotbah")),
            const SizedBox(height: 10),
            Expanded(
                child: TextField(
                    controller: _contentCtrl,
                    maxLines: null,
                    decoration: const InputDecoration(
                        hintText: "Tulis catatan...",
                        border: InputBorder.none))),
          ])),
    );
  }
}

// --- HALAMAN DAFTAR CATATAN ---
class NoteListPage extends StatefulWidget {
  final SharedPreferences prefs;
  final Function(String) formatFunc;
  final Database db;
  final List<Map<String, String>> bibleMeta;
  final Function(String) onJump;
  final Function(String) onOpenNote;

  const NoteListPage({
    super.key,
    required this.prefs,
    required this.formatFunc,
    required this.db,
    required this.bibleMeta,
    required this.onJump,
    required this.onOpenNote,
  });

  @override
  State<NoteListPage> createState() => _NoteListPageState();
}

class _NoteListPageState extends State<NoteListPage> {
  List<String> _keys = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _keys = (widget.prefs.getStringList("ALL_NOTE_KEYS") ?? [])
          .reversed
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Daftar Catatan")),
      body: _keys.isEmpty
          ? const Center(child: Text("Belum ada catatan"))
          : ListView.builder(
              itemCount: _keys.length,
              itemBuilder: (context, i) {
                String? raw = widget.prefs.getString(_keys[i]);
                if (raw == null) return const SizedBox();
                List<String> p = raw.split("~|~");
                return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: ListTile(
                      title: Text(p[1].isEmpty ? "Tanpa Judul" : p[1],
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("${widget.formatFunc(p[0])}\n${p[3]}"),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onOpenNote(_keys[i]);
                      },
                      trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            List<String> all =
                                widget.prefs.getStringList("ALL_NOTE_KEYS") ??
                                    [];
                            all.remove(_keys[i]);
                            await widget.prefs
                                .setStringList("ALL_NOTE_KEYS", all);
                            await widget.prefs.remove(_keys[i]);
                            _load();
                          }),
                    ));
              },
            ),
    );
  }
}