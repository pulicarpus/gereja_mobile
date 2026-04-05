import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'bible_models.dart';

class NoteListPage extends StatefulWidget {
  final SharedPreferences prefs;
  const NoteListPage({super.key, required this.prefs});
  @override
  State<NoteListPage> createState() => _NoteListPageState();
}

class _NoteListPageState extends State<NoteListPage> {
  List<NoteModel> _allNotes = [];
  List<NoteModel> _filteredNotes = [];
  final _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _loadNotes(); }

  void _loadNotes() {
    final keys = widget.prefs.getStringList("ALL_NOTE_KEYS") ?? [];
    List<NoteModel> temp = [];
    for (var k in keys) {
      String? raw = widget.prefs.getString(k);
      if (raw != null) temp.add(NoteModel.fromRaw(k, raw));
    }
    temp.sort((a, b) => b.key.compareTo(a.key));
    setState(() { _allNotes = temp; _filteredNotes = temp; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Catatan Saya")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(hintText: "Cari...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
              onChanged: (q) => setState(() => _filteredNotes = _allNotes.where((n) => n.title.toLowerCase().contains(q.toLowerCase()) || n.content.toLowerCase().contains(q.toLowerCase())).toList()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredNotes.length,
              itemBuilder: (context, i) {
                final note = _filteredNotes[i];
                return ListTile(
                  title: Text(note.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${note.nas} • ${note.date}"),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: note.nas, existingKey: note.key, prefs: widget.prefs))).then((_) => _loadNotes()),
                  onLongPress: () => _confirmDelete(note.key),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String key) {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("Hapus?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("TIDAK")),
        TextButton(onPressed: () async {
          List<String> keys = widget.prefs.getStringList("ALL_NOTE_KEYS") ?? [];
          keys.remove(key);
          await widget.prefs.setStringList("ALL_NOTE_KEYS", keys);
          await widget.prefs.remove(key);
          Navigator.pop(context);
          _loadNotes();
        }, child: const Text("YA")),
      ],
    ));
  }
}

class NoteEditorPage extends StatefulWidget {
  final String nas;
  final String? existingKey;
  final SharedPreferences prefs;
  const NoteEditorPage({super.key, required this.nas, this.existingKey, required this.prefs});
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
      NoteModel n = NoteModel.fromRaw(widget.existingKey!, widget.prefs.getString(widget.existingKey!)!);
      t = n.title; c = n.content;
    }
    _titleCtrl = TextEditingController(text: t);
    _contentCtrl = TextEditingController(text: c);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Editor"), actions: [
        IconButton(icon: const Icon(Icons.check), onPressed: () async {
          String key = widget.existingKey ?? "Note_${DateTime.now().millisecondsSinceEpoch}";
          String date = DateFormat('dd MMM yyyy').format(DateTime.now());
          String data = "${widget.nas}~|~${_titleCtrl.text}~|~ ~|~$date~|~ ~|~${_contentCtrl.text}";
          List<String> keys = widget.prefs.getStringList("ALL_NOTE_KEYS") ?? [];
          if (!keys.contains(key)) keys.add(key);
          await widget.prefs.setStringList("ALL_NOTE_KEYS", keys);
          await widget.prefs.setString(key, data);
          Navigator.pop(context);
        })
      ]),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(widget.nas, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: "Judul")),
            Expanded(child: TextField(controller: _contentCtrl, maxLines: null, decoration: const InputDecoration(hintText: "Tulis isi...", border: InputBorder.none))),
          ],
        ),
      ),
    );
  }
}