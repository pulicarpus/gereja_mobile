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
  String _errorMessage = "";
  int _bookId = 1; 
  int _chapter = 1;
  String _displayTitle = "Memuat..."; 
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    try {
      _prefs = await SharedPreferences.getInstance(); 
      await _initDatabase();
    } catch (e) {
      setState(() => _errorMessage = "Gagal inisialisasi: $e");
    }
  }

  Future<void> _initDatabase() async {
    var dbPath = await getDatabasesPath();
    String path = p.join(dbPath, "TB.SQLite3");
    
    // Paksa copy jika bos merasa file assets berubah tapi di app tidak berubah
    ByteData data = await rootBundle.load("assets/TB.SQLite3");
    List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await File(path).writeAsBytes(bytes, flush: true);
    
    _db = await openDatabase(path);
    _allBooks = await _db!.query('books', orderBy: '_id ASC');
    await _loadContent();
  }

  Future<void> _loadContent() async {
    if (_db == null) return;
    setState(() { _isLoading = true; _errorMessage = ""; });
    
    try {
      // Sesuai screenshot SQLite Editor: book_id, chapter
      final verses = await _db!.query('verses', 
          where: 'book_id = ? AND chapter = ?', 
          whereArgs: [_bookId, _chapter]);
          
      if (mounted) {
        setState(() { 
          _verses = verses; 
          _displayTitle = _allBooks.firstWhere((b) => b['_id'] == _bookId)['name'];
          _isLoading = false; 
          _selectedVerses.clear();
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Error Query: Kolom tidak ditemukan. Coba Reinstall App.\nDetail: $e";
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
        onJumpToBible: (n) => {}, 
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
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : _errorMessage.isNotEmpty 
          ? Center(padding: const EdgeInsets.all(20), child: Text(_errorMessage, style: const TextStyle(color: Colors.red)))
          : ListView.builder(
              itemCount: _verses.length,
              itemBuilder: (context, i) {
                final v = _verses[i];
                final bool isSelected = _selectedVerses.contains(v['verse']);
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: Colors.indigo[50],
                  onTap: () {
                    setState(() { isSelected ? _selectedVerses.remove(v['verse']) : _selectedVerses.add(v['verse']); });
                  },
                  title: RichText(text: TextSpan(style: const TextStyle(color: Colors.black, fontSize: 18, height: 1.5), children: [
                    TextSpan(text: "${v['verse']}. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                    TextSpan(text: v['content'].toString()), // Menggunakan 'content' sesuai SQLite Editor
                  ])),
                );
              },
            ),
      floatingActionButton: _selectedVerses.isNotEmpty ? FloatingActionButton.extended(
        onPressed: () {
          _selectedVerses.sort();
          String nas = "$_displayTitle $_chapter:${_selectedVerses.join(",")}";
          _bukaCatatan(nas);
          setState(() => _selectedVerses.clear());
        },
        label: const Text("Buat Catatan"),
        icon: const Icon(Icons.note_add),
      ) : null,
    );
  }
}