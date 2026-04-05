import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart'; // Untuk fitur kirim
import 'bible_models.dart';
import 'notes_pages.dart';

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
  Map<int, String> _verseNotesMap = {}; // Menyimpan nomor ayat -> Key Catatan
  
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
    await _syncNotes(); // Cari catatan yang ada di bab ini
    
    setState(() {
      _isLoading = false;
      _selectedVerses.clear();
    });
  }

  // Fungsi untuk mensinkronisasi ikon catatan di ujung ayat
  Future<void> _syncNotes() async {
    _verseNotesMap.clear();
    final keys = _prefs.getStringList("ALL_NOTE_KEYS") ?? [];
    String currentBookName = _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    String prefix = "$currentBookName $_currentChapter:";

    for (var k in keys) {
      String? raw = _prefs.getString(k);
      if (raw != null) {
        String nas = raw.split("~|~")[0]; // Ambil NAS (mis: Kejadian 1:1-4)
        if (nas.startsWith(prefix)) {
          // Ambil bagian ayat (mis: 1-4 atau 1,2,3)
          String versesPart = nas.split(":")[1];
          // Ambil ayat terakhir sebagai tempat ikon 📝
          int lastVerse = int.parse(versesPart.split(RegExp(r'[-,]')).last);
          _verseNotesMap[lastVerse] = k;
        }
      }
    }
  }

  // --- MENU AKSI (LONG CLICK) ---
  void _showActionMenu() {
    if (_selectedVerses.isEmpty) return;

    List<int> sorted = _selectedVerses.toList()..sort();
    String bookName = _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    String nas = "$bookName $_currentChapter:${sorted.join(",")}";
    
    // Gabungkan teks ayat untuk Copy/Kirim
    String fullText = "$nas\n";
    for (var vNum in sorted) {
      var vData = _verses.firstWhere((element) => element['verse'] == vNum);
      fullText += "$vNum. ${_cleanVerseText(vData['text'])}\n";
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(nas, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add_comment, color: Colors.green),
              title: const Text("Catatan"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: nas, prefs: _prefs)))
                    .then((_) => _loadContent()); // Refresh setelah simpan
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.blue),
              title: const Text("Salin Ayat"),
              onTap: () {
                Clipboard.setData(ClipboardData(text: fullText));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ayat disalin")));
                setState(() => _selectedVerses.clear());
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.orange),
              title: const Text("Kirim Ayat"),
              onTap: () {
                Share.share(fullText);
                Navigator.pop(context);
                setState(() => _selectedVerses.clear());
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- MODAL NAVIGASI GRID ---
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
              _gridHeader("PERJANJIAN LAMA", Colors.pink),
              _buildGrid(pl),
              _gridHeader("PERJANJIAN BARU", Colors.blue),
              _buildGrid(pb),
            ],
          ),
        );
      },
    );
  }

  Widget _gridHeader(String t, Color c) => Padding(
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
        child: Text(books[i].name.substring(0, 3).toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    String bookName = _allBooks.isEmpty ? "" : _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
        title: GestureDetector(
          onTap: _showNavigation,
          child: Text("$bookName $_currentChapter ▼", style: const TextStyle(fontSize: 18)),
        ),
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        itemCount: _verses.length,
        itemBuilder: (context, i) {
          final v = _verses[i];
          final vNum = v['verse'] as int;
          final vText = _cleanVerseText(v['text'] ?? "");
          final isSelected = _selectedVerses.contains(vNum);
          final noteKey = _verseNotesMap[vNum];

          return GestureDetector(
            onLongPress: () {
              if (!isSelected) setState(() => _selectedVerses.add(vNum));
              _showActionMenu();
            },
            onTap: () {
              setState(() {
                isSelected ? _selectedVerses.remove(vNum) : _selectedVerses.add(vNum);
              });
            },
            child: Container(
              color: isSelected ? Colors.yellow.withOpacity(0.3) : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(color: Colors.black, fontSize: 18, height: 1.5),
                  children: [
                    TextSpan(text: "$vNum. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    TextSpan(text: vText),
                    // IKON CATATAN DI UJUNG AYAT TERAKHIR
                    if (noteKey != null)
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: "", existingKey: noteKey, prefs: _prefs)))
                                .then((_) => _loadContent());
                          },
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Text("📝", style: TextStyle(fontSize: 20)),
                          ),
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