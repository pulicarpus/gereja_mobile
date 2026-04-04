import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'notes_pages.dart'; // Import file baru tadi

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
    try {
      _prefs = await SharedPreferences.getInstance(); 
      _textSize = _prefs.getDouble('text_size') ?? 18.0;
      _refreshNotesIcons(); 
      await _initDatabase();
    } catch (e) { debugPrint(e.toString()); }
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
    if (mounted) setState(() => _noteIconsMap = tempMap);
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
    if (!mounted) return;
    setState(() => _isLoading = true);
    var dbPath = await getDatabasesPath();
    String path = p.join(dbPath, "TB.SQLite3");
    bool exists = await databaseExists(path);
    if (exists) {
      final file = File(path);
      if (await file.length() == 0) exists = false;
    }
    if (!exists) {
      ByteData data = await rootBundle.load("assets/TB.SQLite3");
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
    }
    _db = await openDatabase(path);
    await _loadBooks();
    await _loadContent();
  }

  Future<void> _loadBooks() async {
    if (_db == null) return;
    final books = await _db!.query('books', orderBy: 'book_number ASC');
    if (mounted) setState(() => _allBooks = books);
  }

  Future<void> _loadContent({int? scrollToVerse}) async {
    if (_db == null) return;
    final verses = await _db!.query('verses', where: 'book_number = ? AND chapter = ?', whereArgs: [_bookId, _chapter]);
    String title = "Alkitab";
    if (_bookId > 0 && _bookId <= _bibleMeta.length) title = _bibleMeta[_bookId - 1]['full']!;
    if (mounted) {
      setState(() { _verses = verses; _displayTitle = title; _isLoading = false; _selectedVerses.clear(); });
    }
    if (scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) _scrollController.jumpTo((scrollToVerse - 1) * 85.0);
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
      int bIdx = _bibleMeta.indexWhere((m) => m['full']!.toLowerCase() == kitabName.toLowerCase());
      if (bIdx != -1) {
        setState(() { _bookId = bIdx + 1; _chapter = int.parse(cv[0]); });
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
    ).then((_) { _refreshNotesIcons(); });
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