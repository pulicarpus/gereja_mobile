import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p; // Pakai alias 'p' supaya tidak bentrok dengan BuildContext

class AlkitabPage extends StatefulWidget {
  const AlkitabPage({super.key});

  @override
  State<AlkitabPage> createState() => _AlkitabPageState();
}

class _AlkitabPageState extends State<AlkitabPage> {
  Database? _db;
  List<Map<String, dynamic>> _verses = [];
  Map<int, String> _pericopes = {};
  List<Map<String, dynamic>> _allBooks = [];
  bool _isLoading = true;
  String _errorMessage = "";

  // Status Navigasi (Default Kejadian Pasal 1)
  String _currentVersion = "TB";
  int _bookId = 1; 
  int _chapter = 1;
  String _bookName = "Kejadian";

  // Daftar file sesuai yang ada di assets Bos
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
    try {
      setState(() => _isLoading = true);
      var dbPath = await getDatabasesPath();
      String fileName = _bibleFiles[_currentVersion] ?? "TB.SQLite3";
      
      // Menggunakan p.join karena sudah di-alias
      var path = p.join(dbPath, fileName); 

      if (!await databaseExists(path)) {
        await Directory(p.dirname(path)).create(recursive: true);
        ByteData data = await rootBundle.load("assets/$fileName");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      }

      _db = await openDatabase(path);
      await _loadBooks();
      await _loadData();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Gagal memuat database: $e";
      });
    }
  }

  Future<void> _loadBooks() async {
    if (_db == null) return;
    try {
      final List<Map<String, dynamic>> books = await _db!.query('books');
      setState(() {
        _allBooks = books;
        var activeBook = books.firstWhere((b) {
          int bNum = b['book_number'] ?? b['book_id'];
          return bNum == _bookId || bNum == _bookId * 10;
        });
        _bookName = activeBook['long_name'] ?? activeBook['name'];
      });
    } catch (_) {}
  }

  Future<void> _loadData() async {
    if (_db == null) return;
    try {
      setState(() => _isLoading = true);

      // Deteksi struktur kolom otomatis agar fleksibel
      List<Map<String, dynamic>> columnInfo = await _db!.rawQuery("PRAGMA table_info(verses)");
      String bookCol = columnInfo.any((c) => c['name'] == 'book_number') ? 'book_number' : 'book_id';
      String textCol = columnInfo.any((c) => c['name'] == 'text') ? 'text' : 'content';

      int targetId = (bookCol == 'book_number') ? _bookId * 10 : _bookId;

      final List<Map<String, dynamic>> verses = await _db!.query(
        'verses',
        where: '$bookCol = ? AND chapter = ?',
        whereArgs: [targetId, _chapter],
        orderBy: 'verse ASC',
      );

      Map<int, String> storyMap = {};
      try {
        final List<Map<String, dynamic>> stories = await _db!.query(
          'stories',
          where: '$bookCol = ? AND chapter = ?',
          whereArgs: [targetId, _chapter],
        );
        for (var s in stories) {
          storyMap[s['verse']] = s['title'];
        }
      } catch (_) {}

      setState(() {
        _verses = verses;
        _pericopes = storyMap;
        _isLoading = false;
        _errorMessage = "";
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Gagal memuat ayat: $e";
      });
    }
  }

  void _showBookPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: _allBooks.length,
        itemBuilder: (context, i) {
          final b = _allBooks[i];
          return ListTile(
            title: Text(b['long_name'] ?? b['name']),
            onTap: () {
              Navigator.pop(context);
              int rawId = b['book_number'] ?? b['book_id'];
              _bookId = (rawId >= 10) ? (rawId / 10).round() : rawId;
              _showChapterPicker();
            },
          );
        },
      ),
    );
  }

  void _showChapterPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => GridView.builder(
        padding: const EdgeInsets.all(15),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemCount: 50, 
        itemBuilder: (context, i) => InkWell(
          onTap: () {
            setState(() => _chapter = i + 1);
            _loadData();
            _loadBooks();
            Navigator.pop(context);
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: Text("${i + 1}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ),
        ),
      ),
    );
  }

  String _cleanText(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _showBookPicker,
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
            underline: Container(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            onChanged: (v) {
              if (v != null) {
                setState(() => _currentVersion = v);
                _initDatabase();
              }
            },
            items: ["TB", "TL", "KJV"].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(_errorMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                ))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _verses.length,
                  itemBuilder: (context, index) {
                    final v = _verses[index];
                    final int vNum = v['verse'];
                    final String rawText = v['text'] ?? v['content'] ?? "";
                    final String? perikop = _pericopes[vNum];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (perikop != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 20, bottom: 8),
                            child: Text(perikop, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown)),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 17, color: Colors.black87),
                              children: [
                                TextSpan(text: "$vNum ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                                TextSpan(text: _cleanText(rawText)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}