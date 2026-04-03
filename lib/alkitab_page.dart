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
  int _bookIndex = 1; // 1 = Kejadian, dst.
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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
      debugPrint("Gagal buka DB: $e");
    }
  }

  Future<void> _loadBooks() async {
    if (_db == null) return;
    final List<Map<String, dynamic>> books = await _db!.query('books');
    List<Map<String, dynamic>> ot = [];
    List<Map<String, dynamic>> nt = [];
    for (int i = 0; i < books.length; i++) {
      if (i < 39) ot.add(books[i]); else nt.add(books[i]);
      if ((i + 1) == _bookIndex) {
        var b = books[i];
        _bookName = (b['short_name'] ?? b['long_name'] ?? b['n'] ?? b['name'] ?? "KITAB").toString().toUpperCase();
      }
    }
    setState(() { _booksOT = ot; _booksNT = nt; });
  }

  Future<void> _loadVerses() async {
    if (_db == null) return;
    try {
      setState(() => _isLoading = true);
      
      // 1. CARI TABEL (Deteksi 'verse', 'verses', atau 'bible')
      var tables = await _db!.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      String table = tables.any((t) => t['name'] == 'verse') ? 'verse' : 
                     tables.any((t) => t['name'] == 'verses') ? 'verses' : 'bible';
      
      // 2. CARI KOLOM
      List<Map<String, dynamic>> cols = await _db!.rawQuery("PRAGMA table_info($table)");
      
      // Cek kolom Kitab
      String bCol = cols.any((c) => c['name'] == 'book_id') ? 'book_id' :
                   cols.any((c) => c['name'] == 'book') ? 'book' : 
                   cols.any((c) => c['name'] == 'b') ? 'b' : 'book_number';
      
      // Cek kolom Pasal & Ayat
      String cCol = cols.any((c) => c['name'] == 'chapter') ? 'chapter' : 'c';
      String vNumCol = cols.any((c) => c['name'] == 'verse_number') ? 'verse_number' :
                       cols.any((c) => c['name'] == 'verse') && table != 'verse' ? 'verse' : 'v';
      
      // Cek kolom Teks (Di KJV Bos namanya 'verse')
      String tCol = (table == 'verse' && cols.any((c) => c['name'] == 'verse')) ? 'verse' :
                    cols.any((c) => c['name'] == 'content') ? 'content' :
                    cols.any((c) => c['name'] == 't') ? 't' : 'text';

      // Logika ID (TB pakai ID*10, KJV pakai 1-66)
      int targetId = (bCol == 'book_number') ? _bookIndex * 10 : _bookIndex;

      final List<Map<String, dynamic>> result = await _db!.query(
        table,
        where: '$bCol = ? AND $cCol = ?',
        whereArgs: [targetId, _chapter],
        orderBy: '$vNumCol ASC'
      );

      setState(() {
        _verses = result.map((v) => {
          'number': v[vNumCol],
          'text': v[tCol].toString().replaceAll(RegExp(r'<[^>]*>'), '').trim()
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Gagal load ayat: $e");
      setState(() { _verses = []; _isLoading = false; });
    }
  }

  // --- UI PICKER SEDERHANA ---
  void _showPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            TabBar(controller: _tabController, tabs: const [Tab(text: "PL"), Tab(text: "PB")]),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_grid(0, _booksOT), _grid(39, _booksNT)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(int offset, List<Map<String, dynamic>> list) {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 2),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        var b = list[i];
        String name = (b['short_name'] ?? b['n'] ?? b['name'] ?? "KTB").toString();
        return ActionChip(
          label: Text(name, style: const TextStyle(fontSize: 10)),
          onPressed: () {
            Navigator.pop(ctx);
            _bookIndex = offset + i + 1;
            _bookName = name.toUpperCase();
            _chapter = 1;
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
            items: ["TB", "TL", "KJV"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) { if (v != null) { setState(() { _currentVersion = v; }); _initDatabase(); } },
          )
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        itemCount: _verses.length,
        padding: const EdgeInsets.all(15),
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: RichText(text: TextSpan(
            style: const TextStyle(color: Colors.black, fontSize: 16),
            children: [
              TextSpan(text: "${_verses[i]['number']}. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              TextSpan(text: _verses[i]['text']),
            ]
          )),
        ),
      ),
    );
  }
}