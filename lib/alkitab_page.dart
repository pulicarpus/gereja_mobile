import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
// BERI ALIAS 'p' supaya tidak bentrok dengan BuildContext Flutter
import 'package:path/path.dart' as p;

class AlkitabPage extends StatefulWidget {
  const AlkitabPage({super.key});

  @override
  State<AlkitabPage> createState() => _AlkitabPageState();
}

class _AlkitabPageState extends State<AlkitabPage> {
  Database? _db;
  List<Map<String, dynamic>> _verses = [];
  List<Map<String, dynamic>> _allBooks = [];
  Map<int, String> _pericopes = {};
  bool _isLoading = true;
  String _errorMessage = "";

  String _currentVersion = "TB";
  final Map<String, String> _bibleFiles = {
    "TB": "TB.SQLite3",
    "TL": "TJL.SQLite3",
  };

  int _bookId = 10; 
  int _chapter = 1;
  String _bookName = "Kejadian";

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
      // Gunakan alias p. di sini
      var path = p.join(dbPath, fileName);

      if (!(await databaseExists(path))) {
        // Gunakan alias p. di sini
        await Directory(p.dirname(path)).create(recursive: true);
        ByteData data = await rootBundle.load("assets/$fileName");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      }

      _db = await openDatabase(path, readOnly: true);
      await _loadBooks();
      await _loadData();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Error Database: $e";
      });
    }
  }

  Future<void> _loadBooks() async {
    if (_db == null) return;
    final List<Map<String, dynamic>> books = await _db!.query('books', orderBy: 'book_number ASC');
    setState(() => _allBooks = books);
  }

  Future<void> _loadData() async {
    if (_db == null) return;
    try {
      final List<Map<String, dynamic>> verses = await _db!.query(
        'verses',
        where: 'book_number = ? AND chapter = ?',
        whereArgs: [_bookId, _chapter],
        orderBy: 'verse ASC',
      );

      Map<int, String> storyMap = {};
      if (_currentVersion == "TB") {
        try {
          final List<Map<String, dynamic>> stories = await _db!.query(
            'stories',
            where: 'book_number = ? AND chapter = ?',
            whereArgs: [_bookId, _chapter],
          );
          for (var s in stories) {
            storyMap[s['verse']] = s['title'];
          }
        } catch (_) {}
      }

      setState(() {
        _verses = verses;
        _pericopes = storyMap;
        if (_allBooks.isNotEmpty) {
          _bookName = _allBooks.firstWhere((b) => b['book_number'] == _bookId)['long_name'];
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = "Gagal muat ayat: $e"; });
    }
  }

  void _showPicker() {
    // Sekarang compiler tahu context di sini adalah BuildContext, bukan path Context
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (innerContext) => DefaultTabController(
        length: 2,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const TabBar(
                labelColor: Colors.indigo,
                indicatorColor: Colors.indigo,
                tabs: [Tab(text: "KITAB"), Tab(text: "PASAL")],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    GridView.builder(
                      padding: const EdgeInsets.only(top: 10),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5, mainAxisSpacing: 8, crossAxisSpacing: 8,
                      ),
                      itemCount: _allBooks.length,
                      itemBuilder: (context, i) => InkWell(
                        onTap: () {
                          setState(() => _bookId = _allBooks[i]['book_number']);
                          DefaultTabController.of(context).animateTo(1);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _bookId == _allBooks[i]['book_number'] ? Colors.indigo : Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _allBooks[i]['short_name'],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _bookId == _allBooks[i]['book_number'] ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                    GridView.builder(
                      padding: const EdgeInsets.only(top: 10),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5, mainAxisSpacing: 8, crossAxisSpacing: 8,
                      ),
                      itemCount: 150, // Pasal maksimal (Misal Mazmur ada 150)
                      itemBuilder: (context, i) => InkWell(
                        onTap: () {
                          setState(() {
                            _chapter = i + 1;
                            _isLoading = true;
                          });
                          _loadData();
                          Navigator.pop(context);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _chapter == i + 1 ? Colors.indigo : Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text("${i + 1}"),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showPicker,
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
            underline: const SizedBox(),
            icon: const Icon(Icons.compare_arrows, color: Colors.white),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            onChanged: (v) {
              if (v != null) {
                setState(() { _currentVersion = v; _db = null; });
                _initDatabase();
              }
            },
            items: ["TB", "TL"].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _verses.length,
              itemBuilder: (context, index) {
                final v = _verses[index];
                final String? pTitle = _pericopes[v['verse']];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pTitle != null && _currentVersion == "TB")
                      Padding(
                        padding: const EdgeInsets.only(top: 15, bottom: 5),
                        child: Text(pTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, color: Colors.brown)),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 17, color: Colors.black, height: 1.5),
                          children: [
                            TextSpan(text: "${v['verse']} ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13)),
                            TextSpan(text: v['text'].toString().replaceAll(RegExp(r'<[^>]*>'), '')),
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