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
  String _errorMessage = ""; // Untuk pantau error

  // Sesuaikan ID Buku: Kejadian biasanya 1 atau 10
  int _bookId = 1; 
  int _chapter = 1;

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  Future<void> _initDatabase() async {
    try {
      var dbPath = await getDatabasesPath();
      var path = join(dbPath, "TB.SQLite3");

      // Cek apakah file sudah ada di folder internal
      bool exists = await databaseExists(path);

      if (!exists) {
        debugPrint("Menyalin database dari assets...");
        await Directory(dirname(path)).create(recursive: true);
        
        // Ambil dari assets
        ByteData data = await rootBundle.load("assets/TB.SQLite3");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        
        // Tulis ke file internal
        await File(path).writeAsBytes(bytes, flush: true);
      }

      _db = await openDatabase(path);
      await _loadData();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Gagal inisialisasi: $e";
      });
      debugPrint(_errorMessage);
    }
  }

  Future<void> _loadData() async {
    if (_db == null) return;
    
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = "";
      });

      // 1. Ambil Ayat (Coba cek nama kolom di tabel 'verses')
      // Biasanya kolomnya: book_id, chapter, verse, content/text
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

      Map<int, String> storyMap = {};
      for (var s in stories) {
        storyMap[s['verse']] = s['title'];
      }

      setState(() {
        _verses = verses;
        _pericopes = storyMap;
        _isLoading = false;
      });

      if (verses.isEmpty) {
        setState(() => _errorMessage = "Data ayat tidak ditemukan (Kosong).");
      }

    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Error Query: $e";
      });
      debugPrint(_errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Alkitab Terjemahan Baru"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _errorMessage.isNotEmpty
            ? Center(child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_errorMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              ))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _verses.length,
                itemBuilder: (context, index) {
                  final verse = _verses[index];
                  
                  // CEK NAMA KOLOM: Ganti 'content' jadi 'text' jika error kolom tidak ditemukan
                  final int vNum = verse['verse'] ?? 0;
                  final String content = verse['content'] ?? verse['text'] ?? "";
                  final String? perikopTitle = _pericopes[vNum];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (perikopTitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 20, bottom: 8),
                          child: Text(
                            perikopTitle,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown, fontStyle: FontStyle.italic),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 17, color: Colors.black87),
                            children: [
                              TextSpan(text: "$vNum ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
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