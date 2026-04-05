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
  int _bookId = 1; 
  int _chapter = 1;
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
    
    // Copy dari assets jika belum ada
    if (!(await File(path).exists())) {
      ByteData data = await rootBundle.load("assets/$_currentVersion");
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
    }
    
    _db = await openDatabase(path);
    final bookData = await _db!.query('books', orderBy: '_id ASC');
    _allBooks = bookData.map((e) => BibleBook(id: e['_id'] as int, name: e['name'].toString())).toList();
    await _loadContent();
  }

  Future<void> _loadContent() async {
    final data = await _db!.query('verses', 
        where: 'book_id = ? AND chapter = ?', 
        whereArgs: [_bookId, _chapter]);
    setState(() {
      _verses = data;
      _isLoading = false;
      _selectedVerses.clear();
    });
  }

  // --- UI NAVIGASI ALA KOTLIN (GRID) ---
  void _showNavigation() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => _buildBookGrid(controller),
      ),
    );
  }

  Widget _buildBookGrid(ScrollController scrollController) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text("PILIH KITAB", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        Expanded(
          child: GridView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, childAspectRatio: 2.5, mainAxisSpacing: 8, crossAxisSpacing: 8
            ),
            itemCount: _allBooks.length,
            itemBuilder: (context, i) => InkWell(
              onTap: () {
                setState(() { _bookId = _allBooks[i].id; _chapter = 1; });
                _loadContent();
                Navigator.pop(context);
              },
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                child: Text(_allBooks[i].name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    String currentBookName = _allBooks.isEmpty ? "" : _allBooks.firstWhere((b) => b.id == _bookId).name;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
        title: InkWell(
          onTap: _showNavigation,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text("$currentBookName $_chapter"), const Icon(Icons.arrow_drop_down)],
          ),
        ),
        actions: [
          // Spinner Ganti Versi
          DropdownButton<String>(
            value: _currentVersion,
            dropdownColor: Colors.indigo[900],
            underline: Container(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            items: const [
              DropdownMenuItem(value: "TB.SQLite3", child: Text("TB")),
              DropdownMenuItem(value: "TJL.SQLite3", child: Text("TJL")),
            ],
            onChanged: (v) {
              if (v != null) {
                _currentVersion = v;
                _loadDatabase();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.collections_bookmark),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => NoteListPage(prefs: _prefs))),
          )
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        itemCount: _verses.length,
        itemBuilder: (context, i) {
          final v = _verses[i];
          final verseNum = v['verse'] as int;
          final isSelected = _selectedVerses.contains(verseNum);
          
          return ListTile(
            selected: isSelected,
            selectedTileColor: Colors.blue[50],
            onTap: () {
              setState(() { isSelected ? _selectedVerses.remove(verseNum) : _selectedVerses.add(verseNum); });
            },
            title: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black, fontSize: 18, height: 1.6),
                children: [
                  TextSpan(text: "$verseNum. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  TextSpan(text: v['content'].toString()),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: _selectedVerses.isNotEmpty ? FloatingActionButton.extended(
        onPressed: () {
          List<int> sorted = _selectedVerses.toList()..sort();
          String nas = "$currentBookName $_chapter:${sorted.join(",")}";
          Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: nas, prefs: _prefs)));
          setState(() => _selectedVerses.clear());
        },
        label: const Text("Catat"), icon: const Icon(Icons.edit),
      ) : null,
    );
  }
}