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
  bool _isLoading = true;

  // Default: Kejadian (Book 10) Pasal 1
  // Catatan: Beberapa DB mulai ID Buku dari 10, 100, atau 1. 
  int _bookId = 10; 
  int _chapter = 1;

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  Future<void> _initDatabase() async {
    var dbPath = await getDatabasesPath();
    var path = join(dbPath, "TB.SQLite3");

    var exists = await databaseExists(path);

    if (!exists) {
      try {
        await Directory(dirname(path)).create(recursive: true);
        ByteData data = await rootBundle.load("assets/TB.SQLite3");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      } catch (e) {
        debugPrint("Error copy DB: $e");
      }
    }

    _db = await openDatabase(path);
    _loadData();
  }

  Future<void> _loadData() async {
    if (_db == null) return;
    setState(() => _isLoading = true);

    // 1. Ambil Ayat dari tabel 'verses'
    final List<Map<String, dynamic>> verses = await _db!.query(
      'verses',
      where: 'book_id = ? AND chapter = ?',
      whereArgs: [_bookId, _chapter],
      orderBy: 'verse ASC',
    );

    // 2. Ambil Perikop dari tabel 'stories'
    final List<Map<String, dynamic>> stories = await _db!.query(
      'stories',
      where: 'book_id = ? AND chapter = ?',
      whereArgs: [_bookId, _chapter],
    );

    // Petakan perikop ke nomor ayat
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Alkitab Terjemahan Baru"),
        backgroundColor: const Color(0xFF2196F3),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _verses.length,
            itemBuilder: (context, index) {
              final verse = _verses[index];
              final int vNum = verse['verse'];
              final String content = verse['content'];
              final String? perikopTitle = _pericopes[vNum];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // TAMPILKAN JUDUL PERIKOP JIKA ADA
                  if (perikopTitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 25, bottom: 10),
                      child: Text(
                        perikopTitle,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5D4037), // Cokelat khas Alkitab
                          fontStyle: FontStyle.italic
                        ),
                      ),
                    ),
                  
                  // TAMPILKAN AYAT
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.6),
                        children: [
                          TextSpan(
                            text: "$vNum. ",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold, 
                              color: Colors.blueAccent
                            ),
                          ),
                          TextSpan(text: content),
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