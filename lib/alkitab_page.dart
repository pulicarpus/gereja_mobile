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
      
      if (_db != null) await _db!.close();
      _db = await openDatabase(path);
      
      await _loadBooks();
      await _loadVerses();
    } catch (e) {
      debugPrint("Gagal konek DB: $e");
    }
  }

  Future<void> _loadBooks() async {
    if (_db == null) return;
    try {
      // Ambil data dari tabel 'books'
      final List<Map<String, dynamic>> books = await _db!.query('books', orderBy: 'id ASC');
      List<Map<String, dynamic>> ot = [];
      List<Map<String, dynamic>> nt = [];
      
      for (int i = 0; i < books.length; i++) {
        if (i < 39) ot.add(books[i]); else nt.add(books[i]);
      }

      // Cari kitab yang cocok (berdasarkan urutan index supaya aman antar versi)
      // Kalau TB pindah ke KJV, kita pakai urutan ke-N
      int bookIndex = _selectedBookId > 66 ? 1 : _selectedBookId; 
      // Tapi khusus TB, ID-nya sering dikali 10, kita normalisasi dulu
      if (_selectedBookId % 10 == 0 && _selectedBookId <= 660) bookIndex = _selectedBookId ~/ 10;

      var currentBook = (bookIndex <= books.length) ? books[bookIndex - 1] : books[0];

      setState(() {
        _booksOT = ot;
        _booksNT = nt;
        _selectedBookId = currentBook['id'];
        _bookName = (currentBook['name'] ?? currentBook['short_name'] ?? "KITAB").toString().toUpperCase();
      });
    } catch (e) {
      debugPrint("Gagal load books: $e");
    }
  }

  Future<void> _loadVerses() async {
    if (_db == null) return;
    try {
      setState(() => _isLoading = true);
      
      // 1. CEK NAMA TABEL (Penting: KJV Bos pakai 'verse', TB pakai 'verses')
      var tables = await _db!.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      String activeTable = tables.any((t) => t['name'] == 'verse') ? 'verse' : 
                          tables.any((t) => t['name'] == 'verses') ? 'verses' : 'bible';
      
      // 2. CEK NAMA KOLOM
      List<Map<String, dynamic>> cols = await _db!.rawQuery("PRAGMA table_info($activeTable)");
      
      String bCol = cols.any((c) => c['name'] == 'book_id') ? 'book_id' : 'book_number';
      String vCol = cols.any((c) => c['name'] == 'number') ? 'number' : 
                    cols.any((c) => c['name'] == 'verse_number') ? 'verse_number' : 'verse';
      String tCol = cols.any((c) => c['name'] == 'verse') && activeTable == 'verse' ? 'verse' : 
                    cols.any((c) => c['name'] == 'text') ? 'text' : 'content';

      // 3. QUERY
      final List<Map<String, dynamic>> result = await _db!.query(
        activeTable,
        where: '$bCol = ? AND chapter = ?',
        whereArgs: [_selectedBookId, _chapter],
        orderBy: '$vCol ASC'
      );

      setState(() {
        _verses = result.map((row) => {
          'num': row[vCol],
          'txt': _clean(row[tCol]),
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Query Error: $e");
      setState(() { _verses = []; _isLoading = false; });
    }
  }

  String _clean(dynamic text) {
    if (text == null) return "";
    return text.toString()
        .replaceAll(RegExp(r'<[^>]*>'), '') // Hapus HTML
        .replaceAll(RegExp(r'\{[^}]*\}'), '') // Hapus tag kurung kurawal
        .trim();
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            TabBar(controller: _tabController, labelColor: Colors.blue, tabs: const [Tab(text: "PL"), Tab(text: "PB")]),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_grid(_booksOT), _grid(_booksNT)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<Map<String, dynamic>> data) {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 2.5),
      itemCount: data.length,
      itemBuilder: (ctx, i) {
        String name = data[i]['name'] ?? "KITAB";
        return ActionChip(
          label: Text(name, style: const TextStyle(fontSize: 10)),
          onPressed: () {
            Navigator.pop(ctx);
            setState(() {
              _selectedBookId = data[i]['id'];
              _bookName = name.toUpperCase();
              _chapter = 1;
            });
            _loadVerses();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: InkWell(onTap: _showPicker, child: Text("$_bookName $_chapter")),
        actions: [
          DropdownButton<String>(
            value: _currentVersion,
            onChanged: (v) { if (v != null) { setState(() => _currentVersion = v); _initDatabase(); } },
            items: ["TB", "TL", "KJV"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : _verses.isEmpty 
              ? Center(child: Text("Zonk di ID: $_selectedBookId\nCoba pilih kitab lagi."))
              : ListView.builder(
                  itemCount: _verses.length,
                  padding: const EdgeInsets.all(15),
                  itemBuilder: (ctx, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: "${_verses[i]['num']}. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      TextSpan(text: _verses[i]['txt']),
                    ], style: const TextStyle(fontSize: 17))),
                  ),
                ),
    );
  }
}