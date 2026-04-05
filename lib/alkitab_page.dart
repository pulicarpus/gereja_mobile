import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
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

  Future<void> _initApp() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadDatabase();
  }

  Future<void> _loadDatabase() async {
    setState(() => _isLoading = true);
    var dbPath = await getDatabasesPath();
    String path = p.join(dbPath, _currentVersion);
    
    // Copy database dari assets ke sistem internal tablet
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
    // Mengambil ayat berdasarkan book_number dan chapter
    final data = await _db!.query('verses', 
        where: 'book_number = ? AND chapter = ?', 
        whereArgs: [_currentBookNum, _currentChapter],
        orderBy: 'verse ASC');
        
    setState(() {
      _verses = data;
      _isLoading = false;
      _selectedVerses.clear();
    });
  }

  void _showNavigation() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        List<BibleBook> pl = _allBooks.where((b) => b.bookNumber < 400).toList();
        List<BibleBook> pb = _allBooks.where((b) => b.bookNumber >= 400).toList();

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (_, controller) => SingleChildScrollView(
            controller: controller,
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text("PILIH KITAB", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                _sectionHeader("PERJANJIAN LAMA", Colors.pink),
                _bookGrid(pl),
                _sectionHeader("PERJANJIAN BARU", Colors.blue),
                _bookGrid(pb),
                const SizedBox(height: 30),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _bookGrid(List<BibleBook> books) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 15),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5, childAspectRatio: 1.8, mainAxisSpacing: 6, crossAxisSpacing: 6
      ),
      itemCount: books.length,
      itemBuilder: (context, i) => InkWell(
        onTap: () {
          setState(() { _currentBookNum = books[i].bookNumber; _currentChapter = 1; });
          _loadContent();
          Navigator.pop(context);
        },
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
          child: Text(books[i].name.length > 3 ? books[i].name.substring(0, 3).toUpperCase() : books[i].name.toUpperCase(), 
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
        title: InkWell(
          onTap: _showNavigation,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("$bookName $_currentChapter", style: const TextStyle(fontSize: 17)),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
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
          IconButton(icon: const Icon(Icons.description), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => NoteListPage(prefs: _prefs))))
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        itemCount: _verses.length,
        itemBuilder: (context, i) {
          final v = _verses[i];
          final vNum = v['verse'] as int;
          // PAKAI verse_text SESUAI SQL BOS
          final vText = v['verse_text']?.toString() ?? ""; 
          final isSelected = _selectedVerses.contains(vNum);
          
          return ListTile(
            selected: isSelected,
            selectedTileColor: Colors.blue[50],
            onTap: () {
              setState(() { isSelected ? _selectedVerses.remove(vNum) : _selectedVerses.add(vNum); });
            },
            title: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black, fontSize: 19, height: 1.6),
                children: [
                  TextSpan(text: "$vNum. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  TextSpan(text: vText),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: _selectedVerses.isNotEmpty ? FloatingActionButton.extended(
        backgroundColor: Colors.indigo[900],
        onPressed: () {
          List<int> sorted = _selectedVerses.toList()..sort();
          String nas = "$bookName $_currentChapter:${sorted.join(",")}";
          Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: nas, prefs: _prefs)));
          setState(() => _selectedVerses.clear());
        },
        label: const Text("Catat", style: TextStyle(color: Colors.white)),
        icon: const Icon(Icons.edit, color: Colors.white),
      ) : null,
    );
  }
}