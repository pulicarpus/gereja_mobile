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
  List<Map<String, dynamic>> _allBooks = [];
  bool _isLoading = true;
  String _errorMessage = "";

  // Status Navigasi
  String _currentVersion = "TB";
  int _bookId = 1; // Kita gunakan standar 1-66
  int _chapter = 1;
  String _bookName = "Kejadian";

  // Konfigurasi file (Pastikan sudah ada di assets & pubspec.yaml)
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
      var path = join(dbPath, fileName);

      // Copy file dari assets ke internal storage jika belum ada
      if (!await databaseExists(path)) {
        await Directory(dirname(path)).create(recursive: true);
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
    // Ambil daftar kitab untuk menu navigasi
    final List<Map<String, dynamic>> books = await _db!.query('books');
    setState(() {
      _allBooks = books;
      // Cari nama kitab yang aktif
      try {
        var activeBook = books.firstWhere((b) {
          int bNum = b['book_number'] ?? b['book_id'];
          // Handle perbedaan ID (TB pakai kelipatan 10)
          return bNum == _bookId || bNum == _bookId * 10;
        });
        _bookName = activeBook['long_name'] ?? activeBook['name'];
      } catch (_) {}
    });
  }

  Future<void> _loadData() async {
    if (_db == null) return;
    try {
      setState(() => _isLoading = true);

      // --- DETEKSI STRUKTUR KOLOM OTOMATIS ---
      List<Map<String, dynamic>> columnInfo = await _db!.rawQuery("PRAGMA table_info(verses)");
      
      // Cek apakah pakai 'book_number' (TB) atau 'book_id' (TL/KJV)
      String bookCol = columnInfo.any((c) => c['name'] == 'book_number') ? 'book_number' : 'book_id';
      
      // Cek apakah pakai 'text' (TB) atau 'content' (TL)
      String textCol = columnInfo.any((c) => c['name'] == 'text') ? 'text' : 'content';

      // Sesuaikan ID Buku (TB: 10, 20... | Others: 1, 2...)
      int targetId = (bookCol == 'book_number') ? _bookId * 10 : _bookId;

      // --- AMBIL AYAT ---
      final List<Map<String, dynamic>> verses = await _db!.query(
        'verses',
        where: '$bookCol = ? AND chapter = ?',
        whereArgs: [targetId, _chapter],
        orderBy: 'verse ASC',
      );

      // --- AMBIL PERIKOP (Hanya jika tabel 'stories' ada)
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
      } catch (_) { /* Tabel stories mungkin tidak ada di KJV */ }

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

  // Fungsi navigasi pilih Kitab
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
              // Simpan sebagai ID dasar (1-66)
              _bookId = (rawId >= 10) ? (rawId / 10).round() : rawId;
              _showChapterPicker();
            },
          );
        },
      ),
    );
  }

  // Fungsi navigasi pilih Pasal
  void _showChapterPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => GridView.builder(
        padding: const EdgeInsets.all(15),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5),
        itemCount: 50, // Bisa dibuat dinamis sesuai database
        itemBuilder: (context, i) => InkWell(
          onTap: () {
            setState(() => _chapter = i + 1);
            _loadData();
            _loadBooks(); // Update nama kitab di header
            Navigator.pop(context);
          },
          child: Center(child: Text("${i + 1}", style: const TextStyle(fontSize: 18))),
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
              ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _verses.length,
                  itemBuilder: (context, index) {
                    final v = _verses[index];
                    final int vNum = v['verse'];
                    // Deteksi kolom teks secara fleksibel saat menampilkan
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