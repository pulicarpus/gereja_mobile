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
  int _currentBookNum = 10; // Default Kejadian biasanya 10 atau sesuai SQL
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
    
    // Selalu copy agar update terbaru dari assets masuk
    ByteData data = await rootBundle.load("assets/$_currentVersion");
    List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await File(path).writeAsBytes(bytes, flush: true);
    
    _db = await openDatabase(path);
    
    // Ambil data buku sesuai kolom: book_number & long_name
    final bookData = await _db!.query('books', orderBy: 'book_number ASC');
    _allBooks = bookData.map((e) => BibleBook(
      bookNumber: e['book_number'] as int, 
      name: e['long_name'].toString()
    )).toList();
    
    // Set default book jika belum ada
    if (_allBooks.isNotEmpty && _currentBookNum == 10) {
      _currentBookNum = _allBooks.first.bookNumber;
    }
    
    await _loadContent();
  }

  Future<void> _loadContent() async {
    if (_db == null) return;
    // Query ayat sesuai kolom: book_number, chapter, verse
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (_, controller) => Column(
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text("PILIH KITAB", style: TextStyle(fontWeight: FontWeight.bold))),
            Expanded(
              child: GridView.builder(
                controller: controller,
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, childAspectRatio: 2.2, mainAxisSpacing: 8, crossAxisSpacing: 8
                ),
                itemCount: _allBooks.length,
                itemBuilder: (context, i) => ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black, elevation: 0),
                  onPressed: () {
                    setState(() { _currentBookNum = _allBooks[i].bookNumber; _currentChapter = 1; });
                    _loadContent();
                    Navigator.pop(context);
                  },
                  child: Text(_allBooks[i].name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                ),
              ),
            ),
          ],
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
          child: Text("$bookName $_currentChapter ▼", style: const TextStyle(fontSize: 18)),
        ),
        actions: [
          DropdownButton<String>(
            value: _currentVersion,
            dropdownColor: Colors.indigo[900],
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            underline: Container(),
            items: const [
              DropdownMenuItem(value: "TB.SQLite3", child: Text("TB ")),
              DropdownMenuItem(value: "TJL.SQLite3", child: Text("TJL ")),
            ],
            onChanged: (v) { if (v != null) { _currentVersion = v; _loadDatabase(); } },
          ),
          IconButton(icon: const Icon(Icons.collections_bookmark), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => NoteListPage(prefs: _prefs))))
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        itemCount: _verses.length,
        itemBuilder: (context, i) {
          final v = _verses[i];
          final vNum = v['verse'] as int;
          final isSelected = _selectedVerses.contains(vNum);
          
          return ListTile(
            selected: isSelected,
            selectedTileColor: Colors.blue[50],
            onTap: () {
              setState(() { isSelected ? _selectedVerses.remove(vNum) : _selectedVerses.add(vNum); });
            },
            title: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black, fontSize: 18, height: 1.6),
                children: [
                  TextSpan(text: "$vNum. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  TextSpan(text: v['content'].toString()),
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
        label: const Text("Catat", style: TextStyle(color: Colors.white)), icon: const Icon(Icons.edit, color: Colors.white),
      ) : null,
    );
  }
}