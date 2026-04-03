import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class AlkitabPage extends StatefulWidget {
  const AlkitabPage({super.key});

  @override
  State<AlkitabPage> createState() => _AlkitabPageState();
}

class _AlkitabPageState extends State<AlkitabPage> with TickerProviderStateMixin {
  Database? _db;
  List<Map<String, dynamic>> _verses = [];
  List<Map<String, dynamic>> _booksOT = [];
  List<Map<String, dynamic>> _booksNT = [];
  bool _isLoading = true;
  late TabController _tabController;

  String _currentVersion = "TB";
  int _selectedBookId = 1; 
  int _chapter = 1;
  String _bookName = "KEJADIAN";

  final Map<String, String> _bibleFiles = {
    "TB": "TB.SQLite3",
    "TL": "TJL.SQLite3",
    "KJV": "KJV.SQLite3",
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initDatabase();
  }

  Future<void> _initDatabase() async {
    try {
      setState(() => _isLoading = true);
      var dbPath = await getDatabasesPath();
      String fileName = _bibleFiles[_currentVersion] ?? "TB.SQLite3";
      var path = p.join(dbPath, fileName);

      if (!await databaseExists(path)) {
        await Directory(p.dirname(path)).create(recursive: true);
        ByteData data = await rootBundle.load("assets/$fileName");
        await File(path).writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      _db = await openDatabase(path);
      await _loadBooks();
      await _loadVerses();
    } catch (e) {
      debugPrint("DB Init Error: $e");
    }
  }

  Future<void> _loadBooks() async {
    if (_db == null) return;
    try {
      // Ambil daftar kitab dari tabel 'books'
      final List<Map<String, dynamic>> books = await _db!.query('books', orderBy: 'id ASC');
      List<Map<String, dynamic>> ot = [];
      List<Map<String, dynamic>> nt = [];
      
      for (int i = 0; i < books.length; i++) {
        if (i < 39) ot.add(books[i]); else nt.add(books[i]);
        
        // Cari nama kitab yang sedang aktif
        int bId = books[i]['id'] ?? (i + 1);
        if (bId == _selectedBookId) {
          _bookName = (books[i]['name'] ?? "KITAB").toString().toUpperCase();
        }
      }
      setState(() { _booksOT = ot; _booksNT = nt; });
    } catch (e) {
      debugPrint("Load Books Error: $e");
    }
  }

  Future<void> _loadVerses() async {
    if (_db == null) return;
    try {
      setState(() => _isLoading = true);
      
      // Deteksi struktur (TB pakai book_number, KJV OpenLP pakai book_id)
      List<Map<String, dynamic>> colInfo = await _db!.rawQuery("PRAGMA table_info(verses)");
      bool isTB = colInfo.any((c) => c['name'] == 'book_number');
      
      String bCol = isTB ? 'book_number' : 'book_id';
      String vCol = isTB ? 'verse' : 'number';
      String tCol = isTB ? 'text' : 'text'; // Keduanya pakai 'text' sekarang
      
      // Jika TB, ID dikali 10. Jika KJV OpenLP, pakai ID asli.
      int queryBookId = isTB ? _selectedBookId * 10 : _selectedBookId;

      final List<Map<String, dynamic>> result = await _db!.query(
        'verses',
        where: '$bCol = ? AND chapter = ?',
        whereArgs: [queryBookId, _chapter],
        orderBy: '$vCol ASC'
      );

      setState(() {
        _verses = result;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Load Verses Error: $e");
      setState(() { _verses = []; _isLoading = false; });
    }
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text("PILIH KITAB", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            TabBar(controller: _tabController, labelColor: Colors.blue, unselectedLabelColor: Colors.grey, tabs: const [Tab(text: "PL"), Tab(text: "PB")]),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_gridKitab(_booksOT), _gridKitab(_booksNT)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gridKitab(List<Map<String, dynamic>> data) {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 2.5, mainAxisSpacing: 5, crossAxisSpacing: 5),
      itemCount: data.length,
      itemBuilder: (ctx, i) {
        String name = data[i]['name'] ?? "KITAB";
        int id = data[i]['id'] ?? 1;
        return ActionChip(
          label: Container(width: double.infinity, child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
          onPressed: () {
            Navigator.pop(ctx);
            _selectedBookId = id;
            _bookName = name.toUpperCase();
            _chapter = 1;
            _loadVerses();
          },
        );
      },
    );
  }

  String _cleanHtml(String html) {
    // Membersihkan tag <br/> dan lainnya dari OpenLP
    return html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('{br}', '\n').trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: InkWell(onTap: _showPicker, child: Text("$_bookName $_chapter", style: const TextStyle(color: Colors.blue))),
        actions: [
          DropdownButton<String>(
            value: _currentVersion,
            underline: const SizedBox(),
            onChanged: (v) { if (v != null) { setState(() => _currentVersion = v); _initDatabase(); } },
            items: ["TB", "TL", "KJV"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : ListView.builder(
              itemCount: _verses.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (ctx, i) {
                var v = _verses[i];
                // Handle beda nama kolom antara TB (verse) dan KJV (number)
                var vNum = v['number'] ?? v['verse'] ?? (i + 1);
                var vText = v['text'] ?? "";

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(color: Colors.black, fontSize: 17, height: 1.6),
                      children: [
                        TextSpan(text: "$vNum. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                        TextSpan(text: _cleanHtml(vText.toString())),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}