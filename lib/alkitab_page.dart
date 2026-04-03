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
  int _activeBookId = 1; 
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
      // Ambil dari tabel 'books'
      final List<Map<String, dynamic>> books = await _db!.query('books', orderBy: 'id ASC');
      
      List<Map<String, dynamic>> ot = [];
      List<Map<String, dynamic>> nt = [];
      
      for (int i = 0; i < books.length; i++) {
        if (i < 39) ot.add(books[i]); else nt.add(books[i]);
      }

      // Cari nama kitab yang aktif biar judul di atas bener
      var b = books.firstWhere((e) => e['id'] == _activeBookId, orElse: () => books.first);

      setState(() {
        _booksOT = ot;
        _booksNT = nt;
        _bookName = (b['name'] ?? b['short_name'] ?? "KITAB").toString().toUpperCase();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Gagal load books: $e");
    }
  }

  Future<void> _loadVerses() async {
    if (_db == null) return;
    try {
      setState(() => _isLoading = true);
      
      // Deteksi Tabel: KJV pakai 'verse', TB/TL pakai 'verses'
      var tables = await _db!.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      String activeTable = tables.any((t) => t['name'] == 'verse') ? 'verse' : 'verses';
      
      // Deteksi Kolom
      List<Map<String, dynamic>> cols = await _db!.rawQuery("PRAGMA table_info($activeTable)");
      
      // Kolom Book: TB pakai book_number, KJV pakai book_id
      String bCol = cols.any((c) => c['name'] == 'book_id') ? 'book_id' : 'book_number';
      // Kolom Ayat: KJV pakai number, TB pakai verse
      String vCol = cols.any((c) => c['name'] == 'number') ? 'number' : 'verse';
      // Kolom Teks: INI PENYEBAB KOSONG! KJV teksnya di kolom 'verse', TB di kolom 'text'
      String tCol = (activeTable == 'verse' && cols.any((c) => c['name'] == 'verse')) ? 'verse' : 'text';

      // Khusus TB/TL, ID-nya harus dikali 10 (misal: Kejadian = 10)
      int queryId = (bCol == 'book_number') ? (_activeBookId <= 66 ? _activeBookId * 10 : _activeBookId) : _activeBookId;

      final List<Map<String, dynamic>> result = await _db!.query(
        activeTable,
        where: '$bCol = ? AND chapter = ?',
        whereArgs: [queryId, _chapter],
        orderBy: '$vCol ASC'
      );

      setState(() {
        _verses = result.map((row) => {
          'num': row[vCol],
          'txt': _cleanText(row[tCol])
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() { _verses = []; _isLoading = false; });
    }
  }

  String _cleanText(dynamic text) {
    if (text == null) return "";
    return text.toString()
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .trim();
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder( // PENTING: Pake ini supaya GridView kelihatan
        builder: (context, setModalState) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                labelColor: Colors.blue,
                unselectedLabelColor: Colors.grey,
                tabs: const [Tab(text: "PL"), Tab(text: "PB")]
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [_gridKitab(_booksOT), _gridKitab(_booksNT)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gridKitab(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return const Center(child: Text("Memuat Kitab..."));
    return GridView.builder(
      padding: const EdgeInsets.all(15),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 2.2, mainAxisSpacing: 10, crossAxisSpacing: 10
      ),
      itemCount: data.length,
      itemBuilder: (ctx, i) {
        var b = data[i];
        String name = (b['name'] ?? b['short_name'] ?? "KITAB").toString();
        return ActionChip(
          label: SizedBox(width: double.infinity, child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
          onPressed: () {
            Navigator.pop(ctx);
            setState(() {
              _activeBookId = b['id'];
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
      backgroundColor: Colors.white,
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
          : _verses.isEmpty 
              ? Center(child: Text("Zonk di ID: $_activeBookId\nCoba pilih kitab lagi."))
              : ListView.builder(
                  itemCount: _verses.length,
                  padding: const EdgeInsets.all(15),
                  itemBuilder: (ctx, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: "${_verses[i]['num']}. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 18)),
                      TextSpan(text: "${_verses[i]['txt']}", style: const TextStyle(fontSize: 18)),
                    ])),
                  ),
                ),
    );
  }
}