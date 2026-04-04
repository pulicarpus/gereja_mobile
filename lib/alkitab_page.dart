import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/gestures.dart';

class AlkitabPage extends StatefulWidget {
  const AlkitabPage({super.key});
  @override
  State<AlkitabPage> createState() => _AlkitabPageState();
}

class _AlkitabPageState extends State<AlkitabPage> {
  Database? _db;
  List<Map<String, dynamic>> _verses = [];
  List<Map<String, dynamic>> _allBooks = [];
  List<int> _selectedVerses = [];
  
  // Map untuk menyimpan lokasi ikon catatan (Key: "Kitab Pasal:AyatTerakhir", Value: NoteKey)
  Map<String, String> _noteIconsMap = {}; 
  
  bool _isLoading = true;
  double _textSize = 18.0;
  int _bookId = 1; 
  int _chapter = 1;
  String _displayTitle = "Kejadian"; 

  final ScrollController _scrollController = ScrollController();
  late SharedPreferences _prefs;

  final List<Map<String, String>> _bibleMeta = [
    {"abbr": "KEJ", "full": "Kejadian"}, {"abbr": "KEL", "full": "Keluaran"}, {"abbr": "IMA", "full": "Imamat"}, {"abbr": "BIL", "full": "Bilangan"}, {"abbr": "ULA", "full": "Ulangan"},
    {"abbr": "YOS", "full": "Yosua"}, {"abbr": "HAK", "full": "Hakim-hakim"}, {"abbr": "RUT", "full": "Rut"}, {"abbr": "1SAM", "full": "1 Samuel"}, {"abbr": "2SAM", "full": "2 Samuel"},
    {"abbr": "1RAJ", "full": "1 Raja-raja"}, {"abbr": "2RAJ", "full": "2 Raja-raja"}, {"abbr": "1TAW", "full": "1 Tawarikh"}, {"abbr": "2TAW", "full": "2 Tawarikh"},
    {"abbr": "EZR", "full": "Ezra"}, {"abbr": "NEH", "full": "Nehemia"}, {"abbr": "EST", "full": "Ester"}, {"abbr": "AYU", "full": "Ayub"}, {"abbr": "MAZ", "full": "Mazmur"},
    {"abbr": "AMS", "full": "Amsal"}, {"abbr": "PKH", "full": "Pengkhotbah"}, {"abbr": "KID", "full": "Kidung Agung"}, {"abbr": "YES", "full": "Yesaya"},
    {"abbr": "YER", "full": "Yeremia"}, {"abbr": "RAT", "full": "Ratapan"}, {"abbr": "YEH", "full": "Yehezkiel"}, {"abbr": "DAN", "full": "Daniel"}, {"abbr": "HOS", "full": "Hosea"},
    {"abbr": "YOE", "full": "Yoel"}, {"abbr": "AMO", "full": "Amos"}, {"abbr": "OBA", "full": "Obaja"}, {"abbr": "YUN", "full": "Yunus"}, {"abbr": "MIK", "full": "Mikha"},
    {"abbr": "NAH", "full": "Nahum"}, {"abbr": "HAB", "full": "Habakuk"}, {"abbr": "ZEF", "full": "Zefanya"}, {"abbr": "HAG", "full": "Hagai"}, {"abbr": "ZAK", "full": "Zakharia"}, {"abbr": "MAL", "full": "Maleakhi"},
    {"abbr": "MAT", "full": "Matius"}, {"abbr": "MAR", "full": "Markus"}, {"abbr": "LUK", "full": "Lukas"}, {"abbr": "YOH", "full": "Yohanes"}, {"abbr": "KIS", "full": "Kisah Para Rasul"},
    {"abbr": "ROM", "full": "Roma"}, {"abbr": "1KOR", "full": "1 Korintus"}, {"abbr": "2KOR", "full": "2 Korintus"}, {"abbr": "GAL", "full": "Galatia"}, {"abbr": "EFE", "full": "Efesus"},
    {"abbr": "FIL", "full": "Filipi"}, {"abbr": "KOL", "full": "Kolose"}, {"abbr": "1TES", "full": "1 Tesalonika"}, {"abbr": "2TES", "full": "2 Tesalonika"}, {"abbr": "1TIM", "full": "1 Timotius"},
    {"abbr": "2TIM", "full": "2 Timotius"}, {"abbr": "TIT", "full": "Titus"}, {"abbr": "FLM", "full": "Filemon"}, {"abbr": "IBR", "full": "Ibrani"}, {"abbr": "YAK", "full": "Yakobus"},
    {"abbr": "1PET", "full": "1 Petrus"}, {"abbr": "2PET", "full": "2 Petrus"}, {"abbr": "1YOH", "full": "1 Yohanes"}, {"abbr": "2YOH", "full": "2 Yohanes"}, {"abbr": "3YOH", "full": "3 Yohanes"}, {"abbr": "YUD", "full": "Yudas"}, {"abbr": "WAH", "full": "Wahyu"}
  ];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    _prefs = await SharedPreferences.getInstance(); 
    _textSize = _prefs.getDouble('text_size') ?? 18.0;
    _refreshNotesIcons(); 
    await _initDatabase();
  }

  void _refreshNotesIcons() {
    Map<String, String> tempMap = {};
    List<String> keys = _prefs.getStringList("ALL_NOTE_KEYS") ?? [];
    
    for (String k in keys) {
      String? data = _prefs.getString(k);
      if (data != null && data.contains("~|~")) {
        try {
          String nas = data.split("~|~")[0]; 
          String header = nas.split(":")[0]; 
          List<int> verses = nas.split(":")[1].split(",").map((e) => int.parse(e.trim())).toList();
          verses.sort();
          tempMap["$header:${verses.last}"] = k;
        } catch (e) { }
      }
    }
    setState(() => _noteIconsMap = tempMap);
  }

  String formatNas(String rawNas) {
    try {
      if (!rawNas.contains(":")) return rawNas;
      List<String> parts = rawNas.split(":");
      String head = parts[0];
      List<int> verses = parts[1].split(",").map((e) => int.parse(e.trim())).toList();
      if (verses.length <= 1) return rawNas;
      verses.sort();
      return "$head:${verses.first}-${verses.last}";
    } catch (e) { return rawNas; }
  }

  Future<void> _initDatabase() async {
    setState(() => _isLoading = true);
    var dbPath = await getDatabasesPath();
    String path = p.join(dbPath, "TB.SQLite3");
    if (!(await databaseExists(path))) {
      ByteData data = await rootBundle.load("assets/TB.SQLite3");
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
    }
    _db = await openDatabase(path);
    await _loadBooks();
    await _loadContent();
  }

  Future<void> _loadBooks() async {
    final books = await _db!.query('books', orderBy: 'book_number ASC');
    setState(() => _allBooks = books);
  }

  Future<void> _loadContent({int? scrollToVerse}) async {
    final verses = await _db!.query('verses', where: 'book_number = ? AND chapter = ?', whereArgs: [_bookId, _chapter]);
    int idx = _allBooks.indexWhere((b) => b['book_number'] == _bookId);
    setState(() {
      _verses = verses;
      _displayTitle = (idx >= 0) ? _bibleMeta[idx]['full']! : "Alkitab";
      _isLoading = false;
      _selectedVerses.clear();
    });
    if (scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.jumpTo((scrollToVerse - 1) * 85.0);
      });
    }
  }

  void _jumpToVerse(String nas) {
    try {
      String cleanNas = nas.contains("-") ? nas.split("-")[0] : nas;
      List<String> parts = cleanNas.split(" ");
      String kitabName = parts.length > 2 ? "${parts[0]} ${parts[1]}" : parts[0];
      String chapVerPart = parts.last;
      List<String> cv = chapVerPart.split(":");
      // Perbaikan null safety di bawah ini
      int bIdx = _bibleMeta.indexWhere((m) => m['full']!.toLowerCase() == kitabName.toLowerCase());
      if (bIdx != -1) {
        setState(() { 
          _bookId = _allBooks[bIdx]['book_number']; 
          _chapter = int.parse(cv[0]); 
        });
        _loadContent(scrollToVerse: int.parse(cv[1]));
      }
    } catch(e) { }
  }

  void _bukaCatatan(String nas, {String? existingKey}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => NoteDetailsPage(
        nas: formatNas(nas), rawNas: nas, existingKey: existingKey, prefs: _prefs, db: _db!, bibleMeta: _bibleMeta,
        onJumpToBible: (n) => _jumpToVerse(n),
      )),
    ).then((_) {
      _refreshNotesIcons(); 
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
        title: Text("$_displayTitle $_chapter"),
        actions: [
          IconButton(
            icon: const Icon(Icons.book), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => NoteListPage(
              prefs: _prefs, formatFunc: formatNas, db: _db!, bibleMeta: _bibleMeta,
              onJump: (n) => _jumpToVerse(n),
              onOpenNote: (k) => _bukaCatatan("", existingKey: k),
            )))
          ),
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : Stack(
        children: [
          ListView.builder(
            controller: _scrollController, padding: const EdgeInsets.all(15), itemCount: _verses.length,
            itemBuilder: (context, i) {
              final v = _verses[i];
              final bool isSelected = _selectedVerses.contains(v['verse']);
              String currentVerseKey = "$_displayTitle $_chapter:${v['verse']}";
              String? noteKey = _noteIconsMap[currentVerseKey];

              return InkWell(
                onTap: () => setState(() { isSelected ? _selectedVerses.remove(v['verse']) : _selectedVerses.add(v['verse']); }),
                child: Container(
                  color: isSelected ? Colors.indigo[50] : Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: RichText(text: TextSpan(style: TextStyle(fontSize: _textSize, color: Colors.black87, height: 1.6), children: [
                          TextSpan(text: "${v['verse']}. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                          TextSpan(text: v['text'].replaceAll(RegExp(r'<[^>]*>'), '')),
                        ])),
                      ),
                      if (noteKey != null) 
                        IconButton(
                          padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                          icon: const Icon(Icons.edit_note, color: Colors.orange, size: 28),
                          onPressed: () => _bukaCatatan("", existingKey: noteKey),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_selectedVerses.isNotEmpty) Positioned(top: 0, left: 0, right: 0, child: Container(
            color: Colors.indigo[900], 
            child: Row(children: [
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => _selectedVerses.clear())),
              const Spacer(),
              IconButton(icon: const Icon(Icons.note_add, color: Colors.white), onPressed: () {
                _selectedVerses.sort();
                String nas = "$_displayTitle $_chapter:${_selectedVerses.join(",")}";
                _bukaCatatan(nas);
                setState(() => _selectedVerses.clear());
              }),
            ]),
          )),
        ],
      ),
    );
  }
}

class NoteDetailsPage extends StatefulWidget {
  final String nas; final String rawNas; final String? existingKey; final SharedPreferences prefs;
  final Database db; final List<Map<String, String>> bibleMeta; final Function(String) onJumpToBible;
  const NoteDetailsPage({super.key, required this.nas, required this.rawNas, this.existingKey, required this.prefs, required this.db, required this.bibleMeta, required this.onJumpToBible});
  @override State<NoteDetailsPage> createState() => _NoteDetailsPageState();
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
        displayNas = p[0]; title = p[1].isEmpty ? "Tanpa Judul" : p[1]; content = p[5];
      }
    }
  }

  List<TextSpan> _getParsedContent(String text) {
    List<TextSpan> spans = [];
    final regex = RegExp(r'([1-3]?\s?[A-Za-z]+)\s(\d+):(\d+)(-\d+)?');
    int lastIndex = 0;

    for (var match in regex.allMatches(text)) {
      if (match.start > lastIndex) spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
      String fullMatch = match.group(0)!;
      spans.add(TextSpan(
        text: fullMatch,
        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()..onTap = () => _showFloatingVerse(fullMatch),
      ));
      lastIndex = match.end;
    }
    if (lastIndex < text.length) spans.add(TextSpan(text: text.substring(lastIndex)));
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
        for (int i = int.parse(r[0]); i <= int.parse(r[1]); i++) { ayatRange.add(i); }
      } else { ayatRange.add(int.parse(cv[1])); }

      // Perbaikan null safety di bawah ini
      int bIdx = widget.bibleMeta.indexWhere((m) => m['full']!.toLowerCase() == kitab.toLowerCase());
      if (bIdx == -1) return;
      int bNum = bIdx + 1;

      final data = await widget.db.query('verses', 
        where: 'book_number = ? AND chapter = ? AND verse IN (${ayatRange.join(",")})', 
        whereArgs: [bNum, pasal]);

      if (!mounted) return;
      showModalBottomSheet(
        context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (c) => Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(ref, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo)),
          const Divider(),
          Flexible(child: ListView.builder(shrinkWrap: true, itemCount: data.length, itemBuilder: (cc, idx) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text("${data[idx]['verse']}. ${data[idx]['text'].toString().replaceAll(RegExp(r'<[^>]*>'), '')}"),
          ))),
          const SizedBox(height: 10),
          ElevatedButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); widget.onJumpToBible(ref); }, child: const Text("Buka di Alkitab")),
        ])),
      );
    } catch (e) { }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Isi Catatan"), actions: [
        IconButton(icon: const Icon(Icons.edit), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(
          nas: displayNas, existingKey: widget.existingKey, prefs: widget.prefs,
        ))).then((_) {
          setState(() { _loadData(); }); 
        }))
      ]),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () { Navigator.pop(context); widget.onJumpToBible(displayNas); },
          child: Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.indigo[50], borderRadius: BorderRadius.circular(8)),
            child: Text(displayNas, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo))),
        ),
        const SizedBox(height: 15),
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const Divider(),
        const SizedBox(height: 10),
        RichText(text: TextSpan(style: const TextStyle(fontSize: 18, height: 1.5, color: Colors.black), children: _getParsedContent(content))),
      ])),
    );
  }
}

class NoteEditorPage extends StatefulWidget {
  final String nas; final String? existingKey; final SharedPreferences prefs;
  const NoteEditorPage({super.key, required this.nas, this.existingKey, required this.prefs});
  @override State<NoteEditorPage> createState() => _NoteEditorPageState();
}
class _NoteEditorPageState extends State<NoteEditorPage> {
  late TextEditingController _titleCtrl, _contentCtrl;
  @override void initState() {
    super.initState();
    String t = "", c = "";
    if (widget.existingKey != null) {
      String? data = widget.prefs.getString(widget.existingKey!);
      if (data != null && data.contains("~|~")) { List<String> p = data.split("~|~"); t = p[1]; c = p[5]; }
    }
    _titleCtrl = TextEditingController(text: t); _contentCtrl = TextEditingController(text: c);
  }
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Catatan"), actions: [
        IconButton(icon: const Icon(Icons.save), onPressed: () async {
          String key = widget.existingKey ?? "Note_${DateTime.now().millisecondsSinceEpoch}";
          String data = "${widget.nas}~|~${_titleCtrl.text}~|~-~|~${DateTime.now().toString().substring(0,16)}~|~-~|~${_contentCtrl.text}";
          List<String> keys = widget.prefs.getStringList("ALL_NOTE_KEYS") ?? [];
          if (!keys.contains(key)) { keys.add(key); await widget.prefs.setStringList("ALL_NOTE_KEYS", keys); }
          await widget.prefs.setString(key, data); Navigator.pop(context);
        })
      ]),
      body: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: "Judul Khotbah")),
        const SizedBox(height: 10),
        Expanded(child: TextField(controller: _contentCtrl, maxLines: null, decoration: const InputDecoration(hintText: "Tulis catatan...", border: InputBorder.none))),
      ])),
    );
  }
}

class NoteListPage extends StatefulWidget {
  final SharedPreferences prefs; final Function(String) formatFunc; final Database db; 
  final List<Map<String, String>> bibleMeta; final Function(String) onJump; final Function(String) onOpenNote;
  const NoteListPage({super.key, required this.prefs, required this.formatFunc, required this.db, required this.bibleMeta, required this.onJump, required this.onOpenNote});
  @override State<NoteListPage> createState() => _NoteListPageState();
}
class _NoteListPageState extends State<NoteListPage> {
  List<String> _keys = [];
  @override void initState() { super.initState(); _load(); }
  void _load() { setState(() { _keys = (widget.prefs.getStringList("ALL_NOTE_KEYS") ?? []).reversed.toList(); }); }
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Daftar Catatan")),
      body: _keys.isEmpty ? const Center(child: Text("Belum ada catatan")) : ListView.builder(
        itemCount: _keys.length, itemBuilder: (context, i) {
          String? raw = widget.prefs.getString(_keys[i]); if (raw == null) return const SizedBox();
          List<String> p = raw.split("~|~");
          return Card(margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), child: ListTile(
            title: Text(p[1].isEmpty ? "Tanpa Judul" : p[1], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${widget.formatFunc(p[0])}\n${p[3]}"),
            onTap: () { Navigator.pop(context); widget.onOpenNote(_keys[i]); },
            trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async {
              List<String> all = widget.prefs.getStringList("ALL_NOTE_KEYS") ?? [];
              all.remove(_keys[i]); await widget.prefs.setStringList("ALL_NOTE_KEYS", all); await widget.prefs.remove(_keys[i]); _load();
            }),
          ));
        },
      ),
    );
  }
}