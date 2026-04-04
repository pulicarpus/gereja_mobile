import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'notes_pages.dart';

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
  bool _isLoading = true;
  int _bookId = 1; 
  int _chapter = 1;
  String _displayTitle = "Kejadian"; 
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    _prefs = await SharedPreferences.getInstance(); 
    await _initDatabase();
  }

  Future<void> _initDatabase() async {
    var dbPath = await getDatabasesPath();
    String path = p.join(dbPath, "TB.SQLite3");
    
    if (!(await databaseExists(path))) {
      ByteData data = await rootBundle.load("assets/TB.SQLite3");
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
    }
    
    _db = await openDatabase(path);
    // Ambil daftar kitab langsung dari database
    _allBooks = await _db!.query('books', orderBy: '_id ASC');
    await _loadContent();
  }

  Future<void> _loadContent() async {
    if (_db == null) return;
    setState(() => _isLoading = true);
    
    // QUERY DISESUAIKAN: kolom 'book_id' dan 'content'
    final verses = await _db!.query('verses', 
        where: 'book_id = ? AND chapter = ?', 
        whereArgs: [_bookId, _chapter]);
        
    if (mounted) {
      setState(() { 
        _verses = verses; 
        _displayTitle = _allBooks.firstWhere((b) => b['_id'] == _bookId)['name'];
        _isLoading = false; 
      });
    }
  }

  void _bukaCatatan(String nas, {String? existingKey}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => NoteDetailsPage(
        nas: formatNasRange(nas), 
        rawNas: nas, 
        existingKey: existingKey, 
        prefs: _prefs, 
        db: _db!, 
        allBooks: _allBooks,
        onJumpToBible: (n) => {}, // Implementasi jump jika perlu
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
        title: Text("$_displayTitle $_chapter"),
        actions: [
          IconButton(
            icon: const Icon(Icons.collections_bookmark), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => NoteListPage(
              prefs: _prefs, db: _db!, allBooks: _allBooks,
              onOpenNote: (k) => _bukaCatatan("", existingKey: k),
            )))
          ),
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        itemCount: _verses.length,
        itemBuilder: (context, i) {
          final v = _verses[i];
          final bool isSelected = _selectedVerses.contains(v['verse']);
          return ListTile(
            selected: isSelected,
            onTap: () {
              setState(() { isSelected ? _selectedVerses.remove(v['verse']) : _selectedVerses.add(v['verse']); });
            },
            title: RichText(text: TextSpan(style: const TextStyle(color: Colors.black, fontSize: 18), children: [
              TextSpan(text: "${v['verse']}. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
              TextSpan(text: v['content'].toString()), // KOLOM 'content'
            ])),
          );
        },
      ),
      floatingActionButton: _selectedVerses.isNotEmpty ? FloatingActionButton(
        onPressed: () {
          _selectedVerses.sort();
          _bukaCatatan("$_displayTitle $_chapter:${_selectedVerses.join(",")}");
          setState(() => _selectedVerses.clear());
        },
        child: const Icon(Icons.note_add),
      ) : null,
    );
  }
}