import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AlkitabPage extends StatefulWidget {
  const AlkitabPage({super.key});

  @override
  State<AlkitabPage> createState() => _AlkitabPageState();
}

class _AlkitabPageState extends State<AlkitabPage> {
  Database? _db;
  List<Map<String, dynamic>> _verses = [];
  Map<int, String> _pericopes = {};
  List<Map<String, dynamic>> _allBooks = []; // Untuk daftar navigasi
  bool _isLoading = true;

  String _currentVersion = "TB";
  int _bookId = 10; // Default: Kejadian
  int _chapter = 1;
  String _bookName = "Kejadian";

  final Map<String, String> _bibleFiles = {
    "TB": "TB.SQLite3",
    "TL": "TJL.SQLite3",
    "KJV": "KJV.SQLite3",
  };

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  Future<void> _initDatabase() async {
    setState(() => _isLoading = true);
    var dbPath = await getDatabasesPath();
    String fileName = _bibleFiles[_currentVersion] ?? "TB.SQLite3";
    var path = join(dbPath, fileName);

    if (!await databaseExists(path)) {
      ByteData data = await rootBundle.load("assets/$fileName");
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
    }

    _db = await openDatabase(path);
    await _loadBooks(); // Ambil daftar kitab dulu
    await _loadData();
  }

  // Ambil daftar semua kitab untuk menu navigasi
  Future<void> _loadBooks() async {
    if (_db == null) return;
    final List<Map<String, dynamic>> books = await _db!.query('books');
    setState(() {
      _allBooks = books;
      // Update nama kitab yang sedang dibuka
      _bookName = books.firstWhere((b) => b['book_number'] == _bookId)['long_name'];
    });
  }

  Future<void> _loadData() async {
    if (_db == null) return;
    final List<Map<String, dynamic>> verses = await _db!.query(
      'verses',
      where: 'book_number = ? AND chapter = ?',
      whereArgs: [_bookId, _chapter],
      orderBy: 'verse ASC',
    );

    final List<Map<String, dynamic>> stories = await _db!.query(
      'stories',
      where: 'book_number = ? AND chapter = ?',
      whereArgs: [_bookId, _chapter],
    );

    Map<int, String> storyMap = {};
    for (var s in stories) {
      storyMap[s['verse']] = s['title'];
    }

    setState(() {
      _verses = verses;
      _pericopes = storyMap;
      _isLoading = false;
    });
  }

  // FUNGSI NAVIGASI: Munculkan pilihan Kitab
  void _showNavigation() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(10),
          child: ListView.builder(
            itemCount: _allBooks.length,
            itemBuilder: (context, index) {
              final b = _allBooks[index];
              return ListTile(
                title: Text(b['long_name']),
                onTap: () {
                  Navigator.pop(context);
                  _showChapterPicker(b['book_number'], b['long_name']);
                },
              );
            },
          ),
        );
      },
    );
  }

  // FUNGSI NAVIGASI: Munculkan pilihan Pasal
  void _showChapterPicker(int bookId, String bookName) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return GridView.builder(
          padding: const EdgeInsets.all(15),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5),
          itemCount: 50, // Idealnya ambil max chapter dari DB, ini contoh static 50
          itemBuilder: (context, index) {
            int chap = index + 1;
            return InkWell(
              onTap: () {
                setState(() {
                  _bookId = bookId;
                  _chapter = chap;
                  _bookName = bookName;
                });
                _loadData();
                Navigator.pop(context);
              },
              child: Center(child: Text("$chap", style: const TextStyle(fontSize: 18))),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Judul bisa diklik untuk navigasi
        title: GestureDetector(
          onTap: _showNavigation,
          child: Row(
            children: [
              Text("$_bookName $_chapter"),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          DropdownButton<String>(
            value: _currentVersion,
            dropdownColor: Colors.indigo,
            style: const TextStyle(color: Colors.white),
            onChanged: (v) {
              if (v != null) {
                setState(() => _currentVersion = v);
                _initDatabase();
              }
            },
            items: ["TB", "TL", "KJV"].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : ListView.builder(
            itemCount: _verses.length,
            itemBuilder: (context, index) {
              final v = _verses[index];
              final perikop = _pericopes[v['verse']];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (perikop != null)
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(perikop, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.brown)),
                    ),
                  ListTile(
                    leading: Text("${v['verse']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                    title: Text(v['text'].replaceAll(RegExp(r'<[^>]*>'), '')),
                  ),
                ],
              );
            },
          ),
    );
  }
}