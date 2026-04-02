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
  String _errorMessage = "";

  // Sesuai screenshot Bos: Kejadian = 10
  final int _bookId = 10; 
  final int _chapter = 1;

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  Future<void> _initDatabase() async {
    try {
      var dbPath = await getDatabasesPath();
      var path = join(dbPath, "TB.SQLite3");

      bool exists = await databaseExists(path);

      if (!exists) {
        await Directory(dirname(path)).create(recursive: true);
        ByteData data = await rootBundle.load("assets/TB.SQLite3");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      }

      _db = await openDatabase(path);
      await _loadData();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Gagal buka database: $e";
      });
    }
  }

  Future<void> _loadData() async {
    if (_db == null) return;
    
    try {
      setState(() => _isLoading = true);

      // 1. Ambil Ayat (Sesuai kolom: book_number, chapter, verse, text)
      final List<Map<String, dynamic>> verses = await _db!.query(
        'verses',
        where: 'book_number = ? AND chapter = ?',
        whereArgs: [_bookId, _chapter],
        orderBy: 'verse ASC',
      );

      // 2. Ambil Perikop (Sesuai kolom: book_number, chapter, verse, title)
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

    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Error Query: $e";
      });
    }
  }

  // Fungsi untuk membersihkan tag <pb/> atau <f>...</f> agar teks bersih
  String _cleanText(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Alkitab TB"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _errorMessage.isNotEmpty
            ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _verses.length,
                itemBuilder: (context, index) {
                  final verse = _verses[index];
                  final int vNum = verse['verse'];
                  final String rawText = verse['text'] ?? "";
                  final String? perikopTitle = _pericopes[vNum];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (perikopTitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 20, bottom: 8),
                          child: Text(
                            perikopTitle,
                            style: const TextStyle(
                              fontSize: 18, 
                              fontWeight: FontWeight.bold, 
                              color: Colors.brown,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 17, color: Colors.black87),
                            children: [
                              TextSpan(
                                text: "$vNum ", 
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)
                              ),
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