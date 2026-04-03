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

  // Pengaturan Versi & Lokasi (Sesuai Screenshot Drive Bos)
  String _currentVersion = "TB"; 
  final Map<String, String> _bibleFiles = {
    "TB": "TB.SQLite3",
    "TL": "TJL.SQLite3", // Nama file di Drive Bos adalah TJL.SQLite3
  };

  int _bookId = 10; // Kejadian
  int _chapter = 1;

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  // Fungsi untuk ganti versi Alkitab
  void _changeVersion(String? newVersion) {
    if (newVersion != null && newVersion != _currentVersion) {
      setState(() {
        _currentVersion = newVersion;
        _db = null; // Reset koneksi DB
      });
      _initDatabase();
    }
  }

  Future<void> _initDatabase() async {
    try {
      setState(() => _isLoading = true);
      var dbPath = await getDatabasesPath();
      String fileName = _bibleFiles[_currentVersion] ?? "TB.SQLite3";
      var path = join(dbPath, fileName);

      bool exists = await databaseExists(path);

      if (!exists) {
        await Directory(dirname(path)).create(recursive: true);
        // Pastikan file ini sudah didaftarkan di pubspec.yaml assets
        ByteData data = await rootBundle.load("assets/$fileName");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      }

      _db = await openDatabase(path);
      await _loadData();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "File $currentVersion belum ada di assets: $e";
      });
    }
  }

  Future<void> _loadData() async {
    if (_db == null) return;
    try {
      // Query Verses (Sesuai kolom di SQLite Editor Bos)
      final List<Map<String, dynamic>> verses = await _db!.query(
        'verses',
        where: 'book_number = ? AND chapter = ?',
        whereArgs: [_bookId, _chapter],
        orderBy: 'verse ASC',
      );

      // Query Stories/Perikop
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
        _errorMessage = "";
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Gagal memuat data: $e";
      });
    }
  }

  String _cleanText(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Alkitab Mobile"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          // Tombol Pilih Versi
          DropdownButton<String>(
            value: _currentVersion,
            dropdownColor: Colors.indigo,
            underline: Container(),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            onChanged: _changeVersion,
            items: ["TB", "TL"].map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
          ),
          const SizedBox(width: 15),
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
                            child: Text(perikopTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown)),
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