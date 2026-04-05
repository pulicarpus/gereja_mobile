import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'bible_models.dart';
import 'notes_pages.dart';
import 'search_page.dart';

class AlkitabPage extends StatefulWidget {
  const AlkitabPage({super.key});
  @override
  State<AlkitabPage> createState() => _AlkitabPageState();
}

class _AlkitabPageState extends State<AlkitabPage> {
  Database? _db;
  List<Map<String, dynamic>> _verses = [];
  List<BibleBook> _allBooks = [];
  Set<int> _selectedVerses = {};
  Map<int, List<String>> _verseNotesMap = {}; 
  
  String _currentVersion = "TB.SQLite3"; 
  int _currentBookNum = 10; 
  int _currentChapter = 1;
  bool _isLoading = true;
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  String _cleanVerseText(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  Future<void> _initApp() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadDatabase();
  }

  Future<void> _loadDatabase() async {
    setState(() => _isLoading = true);
    var dbPath = await getDatabasesPath();
    String path = p.join(dbPath, _currentVersion);
    
    ByteData data = await rootBundle.load("assets/$_currentVersion");
    List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await File(path).writeAsBytes(bytes, flush: true);
    
    _db = await openDatabase(path);
    final bookData = await _db!.query('books', orderBy: 'book_number ASC');
    
    setState(() {
      _allBooks = bookData.map((e) => BibleBook(
        bookNumber: e['book_number'] as int, 
        name: e['long_name'].toString()
      )).toList();
    });
    
    await _loadContent();
  }

  Future<void> _loadContent() async {
    if (_db == null) return;
    final data = await _db!.query('verses', 
        where: 'book_number = ? AND chapter = ?', 
        whereArgs: [_currentBookNum, _currentChapter],
        orderBy: 'verse ASC');
        
    _verses = data;
    await _syncNotes(); 
    
    setState(() {
      _isLoading = false;
      _selectedVerses.clear();
    });
  }

  Future<void> _syncNotes() async {
    _verseNotesMap.clear();
    final keys = _prefs.getStringList("ALL_NOTE_KEYS") ?? [];
    if (_allBooks.isEmpty) return;
    
    String currentBookName = _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    String prefix = "$currentBookName $_currentChapter:";

    for (var k in keys) {
      String? raw = _prefs.getString(k);
      if (raw != null) {
        String nas = raw.split("~|~")[0];
        if (nas.startsWith(prefix)) {
          try {
            String versesPart = nas.split(":")[1];
            int lastVerse = int.parse(versesPart.split(RegExp(r'[-,]')).last);
            if (!_verseNotesMap.containsKey(lastVerse)) {
              _verseNotesMap[lastVerse] = [];
            }
            _verseNotesMap[lastVerse]!.add(k);
          } catch (e) { print("Error parse: $e"); }
        }
      }
    }
  }

  // --- MODAL PEMILIHAN KITAB (YANG TADI HILANG) ---
  void _showNavigation() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        List<BibleBook> pl = _allBooks.where((b) => b.bookNumber < 400).toList();
        List<BibleBook> pb = _allBooks.where((b) => b.bookNumber >= 400).toList();
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          builder: (_, controller) => ListView(
            controller: controller,
            children: [
              const SizedBox(height: 20),
              _sectionTitle("PERJANJIAN LAMA", Colors.pink),
              _buildGrid(pl),
              _sectionTitle("PERJANJIAN BARU", Colors.blue),
              _buildGrid(pb),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String t, Color c) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold)),
  );

  Widget _buildGrid(List<BibleBook> books) => GridView.builder(
    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, childAspectRatio: 2, mainAxisSpacing: 5, crossAxisSpacing: 5),
    itemCount: books.length,
    itemBuilder: (context, i) => InkWell(
      onTap: () {
        setState(() { _currentBookNum = books[i].bookNumber; _currentChapter = 1; });
        _loadContent();
        Navigator.pop(context);
      },
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(5)),
        child: Text(books[i].name.substring(0, books[i].name.length > 3 ? 3 : books[i].name.length).toUpperCase(), 
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    ),
  );

  void _showActionMenu() {
    if (_selectedVerses.isEmpty) return;
    List<int> sorted = _selectedVerses.toList()..sort();
    String bookName = _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    String nas = "$bookName $_currentChapter:${sorted.join(",")}";
    
    String fullText = "$nas\n";
    for (var vNum in sorted) {
      var vData = _verses.firstWhere((element) => element['verse'] == vNum);
      fullText += "$vNum. ${_cleanVerseText(vData['text'])}\n";
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(nas, style: const TextStyle(fontWeight: FontWeight.bold))),
          ListTile(leading: const Icon(Icons.add_comment, color: Colors.blue), title: const Text("Catatan Baru"), 
            onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: nas, prefs: _prefs))).then((_) => _loadContent()); }),
          ListTile(leading: const Icon(Icons.copy), title: const Text("Salin"), 
            onTap: () { Clipboard.setData(ClipboardData(text: fullText)); Navigator.pop(context); setState(() => _selectedVerses.clear()); }),
          ListTile(leading: const Icon(Icons.share), title: const Text("Kirim"), onTap: () { Share.share(fullText); Navigator.pop(context); }),
        ],
      ),
    );
  }

  void _showMultipleNotesPicker(List<String> keys) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Pilih Catatan"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: keys.length,
            itemBuilder: (context, i) {
              String? raw = _prefs.getString(keys[i]);
              String title = raw?.split("~|~")[1] ?? "Tanpa Judul";
              return ListTile(leading: const Text("📝"), title: Text(title),
                onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: "", existingKey: keys[i], prefs: _prefs))).then((_) => _loadContent()); });
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String bookName = _allBooks.isEmpty ? "" : _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
        title: InkWell(onTap: _showNavigation, child: Text("$bookName $_currentChapter ▼", style: const TextStyle(fontSize: 18))),
        actions: [
          DropdownButton<String>(
            value: _currentVersion,
            dropdownColor: Colors.indigo[900],
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: "TB.SQLite3", child: Text("TB ")),
              DropdownMenuItem(value: "TJL.SQLite3", child: Text("TJL ")),
            ],
            onChanged: (v) { if (v != null) { _currentVersion = v; _loadDatabase(); } },
          ),
          IconButton(icon: const Icon(Icons.search), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => SearchPage(db: _db!, allBooks: _allBooks))).then((res) {
            if (res != null) { setState(() { _currentBookNum = res['book_number']; _currentChapter = res['chapter']; }); _loadContent(); }
          })),
          IconButton(icon: const Icon(Icons.event_note), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => NoteListPage(prefs: _prefs)))),
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        itemCount: _verses.length,
        itemBuilder: (context, i) {
          final v = _verses[i];
          final vNum = v['verse'] as int;
          final isSelected = _selectedVerses.contains(vNum);
          final noteKeys = _verseNotesMap[vNum];

          return GestureDetector(
            onLongPress: () { if (!isSelected) setState(() => _selectedVerses.add(vNum)); _showActionMenu(); },
            onTap: () => setState(() => isSelected ? _selectedVerses.remove(vNum) : _selectedVerses.add(vNum)),
            child: Container(
              color: isSelected ? Colors.yellow.withOpacity(0.2) : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(color: Colors.black, fontSize: 18, height: 1.5),
                  children: [
                    TextSpan(text: "$vNum. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    TextSpan(text: _cleanVerseText(v['text'])),
                    if (noteKeys != null)
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () => noteKeys.length > 1 ? _showMultipleNotesPicker(noteKeys) : Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: "", existingKey: noteKeys[0], prefs: _prefs))).then((_) => _loadContent()),
                          child: const Padding(padding: EdgeInsets.only(left: 8), child: Text("📝", style: TextStyle(fontSize: 22))),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}