import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

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
  Map<String, String> _savedNotes = {}; 
  
  bool _isLoading = true;
  bool _isSearching = false;
  double _textSize = 18.0;
  String _currentVersion = "TB"; 
  int _bookId = 10; 
  int _chapter = 1;
  String _displayTitle = "Kejadian"; 

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
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
    _refreshNotesCache();
    await _initDatabase();
  }

  void _refreshNotesCache() {
    Map<String, String> tempNotes = {};
    List<String> keys = _prefs.getStringList("ALL_NOTE_KEYS") ?? [];
    for (String k in keys) {
      String? data = _prefs.getString(k);
      if (data != null) {
        try {
          String nas = data.split("~|~")[0];
          String kitabPasal = nas.split(":")[0];
          List<String> listAyat = nas.split(":")[1].split(",");
          for (var a in listAyat) {
            tempNotes["$kitabPasal:$a"] = k; // Simpan KEY catatan di sini
          }
        } catch (e) { debugPrint("Error cache: $e"); }
      }
    }
    setState(() => _savedNotes = tempNotes);
  }

  Future<void> _initDatabase() async {
    setState(() => _isLoading = true);
    var dbPath = await getDatabasesPath();
    String fileName = "$_currentVersion.SQLite3";
    var path = p.join(dbPath, fileName);
    if (!(await databaseExists(path))) {
      ByteData data = await rootBundle.load("assets/$fileName");
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
    }
    if (_db != null) await _db!.close();
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
        _scrollController.jumpTo((scrollToVerse - 1) * 80.0);
      });
    }
  }

  void _bukaEditor(String nas, String isi, {String? existingKey}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => NoteEditorPage(
        nas: nas, isiAyat: isi, existingKey: existingKey, prefs: _prefs,
        onJumpToBible: (nasTarget) => _jumpToVerse(nasTarget),
      )),
    ).then((_) => _refreshNotesCache());
  }

  void _jumpToVerse(String nas) {
    try {
      List<String> parts = nas.split(" ");
      String kitabName = parts.length > 2 ? "${parts[0]} ${parts[1]}" : parts[0];
      String chapVerPart = parts.length > 2 ? parts[2] : parts[1];
      List<String> cv = chapVerPart.split(":");
      int bIdx = _bibleMeta.indexWhere((m) => m['full'] == kitabName);
      if (bIdx != -1) {
        setState(() { _bookId = _allBooks[bIdx]['book_number']; _chapter = int.parse(cv[0]); });
        _loadContent(scrollToVerse: int.parse(cv[1].split(",")[0]));
      }
    } catch(e) { debugPrint("Jump error: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : Stack(
        children: [
          ListView.builder(
            controller: _scrollController, padding: const EdgeInsets.all(15), itemCount: _verses.length,
            itemBuilder: (context, i) {
              final v = _verses[i];
              final bool isSelected = _selectedVerses.contains(v['verse']);
              String currentNasKey = "$_displayTitle $_chapter:${v['verse']}";
              String? noteKey = _savedNotes[currentNasKey];

              return InkWell(
                onTap: () => setState(() { isSelected ? _selectedVerses.remove(v['verse']) : _selectedVerses.add(v['verse']); }),
                child: Container(
                  color: isSelected ? Colors.indigo[50] : Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: RichText(text: TextSpan(style: TextStyle(fontSize: _textSize, color: Colors.black87, height: 1.6), children: [
                        TextSpan(text: "${v['verse']}. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                        TextSpan(text: v['text'].replaceAll(RegExp(r'<[^>]*>'), '')),
                      ]))),
                      if (noteKey != null) IconButton(
                        icon: const Icon(Icons.edit_note, color: Colors.orange, size: 28),
                        onPressed: () {
                          String? data = _prefs.getString(noteKey);
                          if(data != null) {
                            List<String> p = data.split("~|~");
                            _bukaEditor(p[0], "Klik untuk melihat ayat", existingKey: noteKey);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_selectedVerses.isNotEmpty) _buildSelectionToolbar(),
        ],
      ),
    );
  }

  Widget _buildSelectionToolbar() {
    return Positioned(top: 0, left: 0, right: 0, child: Container(color: Colors.indigo[900], child: Row(children: [
      IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => _selectedVerses.clear())),
      const Spacer(),
      IconButton(icon: const Icon(Icons.note_add, color: Colors.white), onPressed: () {
        _selectedVerses.sort();
        String nas = "$_displayTitle $_chapter:${_selectedVerses.join(",")}";
        _bukaEditor(nas, "Ayat terpilih...");
        setState(() => _selectedVerses.clear());
      }),
    ])));
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
      title: Text("$_displayTitle $_chapter"),
      actions: [
        IconButton(icon: const Icon(Icons.book), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => NoteListPage(prefs: _prefs, onNoteSelected: (k) {
          String? data = _prefs.getString(k);
          if(data != null) {
            List<String> p = data.split("~|~");
            _bukaEditor(p[0], "Isi Catatan", existingKey: k);
          }
        })))),
      ],
    );
  }
}

class NoteEditorPage extends StatefulWidget {
  final String nas; final String isiAyat; final String? existingKey; final SharedPreferences prefs;
  final Function(String) onJumpToBible;
  const NoteEditorPage({super.key, required this.nas, required this.isiAyat, this.existingKey, required this.prefs, required this.onJumpToBible});
  @override State<NoteEditorPage> createState() => _NoteEditorPageState();
}
class _NoteEditorPageState extends State<NoteEditorPage> {
  late TextEditingController _titleCtrl, _contentCtrl;
  @override
  void initState() {
    super.initState();
    String t = "", c = "";
    if (widget.existingKey != null) {
      List<String> p = widget.prefs.getString(widget.existingKey!)!.split("~|~");
      t = p[1]; c = p[5];
    }
    _titleCtrl = TextEditingController(text: t);
    _contentCtrl = TextEditingController(text: c);
  }
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Isi Catatan"), actions: [IconButton(icon: const Icon(Icons.save), onPressed: () async {
        String key = widget.existingKey ?? "Note_${DateTime.now().millisecondsSinceEpoch}";
        String data = "${widget.nas}~|~${_titleCtrl.text}~|~-~|~${DateTime.now()}~|~-~|~${_contentCtrl.text}";
        if (widget.existingKey == null) {
          List<String> keys = widget.prefs.getStringList("ALL_NOTE_KEYS") ?? [];
          keys.add(key); await widget.prefs.setStringList("ALL_NOTE_KEYS", keys);
        }
        await widget.prefs.setString(key, data);
        Navigator.pop(context);
      })]),
      body: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        InkWell(
          onTap: () { Navigator.pop(context); widget.onJumpToBible(widget.nas); },
          child: Container(padding: const EdgeInsets.all(10), color: Colors.blue[50], child: Text(widget.nas, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
        ),
        TextField(controller: _titleCtrl, decoration: const InputDecoration(hintText: "Judul")),
        Expanded(child: TextField(controller: _contentCtrl, maxLines: null, decoration: const InputDecoration(hintText: "Mulai menulis...", border: InputBorder.none))),
      ])),
    );
  }
}

class NoteListPage extends StatelessWidget {
  final SharedPreferences prefs; final Function(String) onNoteSelected;
  const NoteListPage({super.key, required this.prefs, required this.onNoteSelected});
  @override Widget build(BuildContext context) {
    List<String> keys = (prefs.getStringList("ALL_NOTE_KEYS") ?? []).reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text("Daftar Catatan")),
      body: ListView.builder(
        itemCount: keys.length,
        itemBuilder: (context, i) {
          String? raw = prefs.getString(keys[i]);
          if (raw == null) return const SizedBox();
          List<String> p = raw.split("~|~");
          return ListTile(
            title: Text(p[1].isEmpty ? "Tanpa Judul" : p[1]),
            subtitle: Text(p[0]),
            onTap: () => onNoteSelected(keys[i]),
          );
        },
      ),
    );
  }
}