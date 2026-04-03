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
  int _selectedBookIndex = 1; // 1 = Kejadian, 2 = Keluaran, dst.
  int _chapter = 1;
  String _bookName = "KEJADIAN";

  final Map<String, String> _bibleFiles = {
    "TB": "TB.SQLite3",
    "TL": "TJL.SQLite3",
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
      debugPrint("DB Error: $e");
    }
  }

  Future<void> _loadBooks() async {
    if (_db == null) return;
    try {
      // TB/TL biasanya pakai tabel 'books'
      final List<Map<String, dynamic>> books = await _db!.query('books', orderBy: 'id ASC');
      List<Map<String, dynamic>> ot = [];
      List<Map<String, dynamic>> nt = [];
      
      for (int i = 0; i < books.length; i++) {
        if (i < 39) ot.add(books[i]); else nt.add(books[i]);
      }

      // Cari nama kitab yang aktif berdasarkan index pilihan
      // Ingat: ID di DB bisa 10, 20, 30... jadi kita cari yang matches
      var b = books.firstWhere(
        (e) => e['id'] == _selectedBookIndex * 10 || e['id'] == _selectedBookIndex, 
        orElse: () => books.first
      );

      setState(() {
        _booksOT = ot;
        _booksNT = nt;
        _bookName = (b['name'] ?? "KITAB").toString().toUpperCase();
      });
    } catch (e) {
      debugPrint("Load Books Error: $e");
    }
  }

  Future<void> _loadVerses() async {
    if (_db == null) return;
    try {
      setState(() => _isLoading = true);
      
      // Khusus TB & TL: 
      // Tabel: verses
      // Kolom ID Kitab: book_number (isinya 10, 20, 30...)
      // Kolom Ayat: verse
      // Kolom Teks: text
      
      int queryId = _selectedBookIndex * 10; 

      final List<Map<String, dynamic>> result = await _db!.query(
        'verses',
        where: 'book_number = ? AND chapter = ?',
        whereArgs: [queryId, _chapter],
        orderBy: 'verse ASC'
      );

      setState(() {
        _verses = result;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Query Error: $e");
      setState(() { _verses = []; _isLoading = false; });
    }
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            const SizedBox(height: 10),
            TabBar(
              controller: _tabController,
              labelColor: Colors.blue,
              tabs: const [Tab(text: "PL"), Tab(text: "PB")]
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_gridKitab(_booksOT, 0), _gridKitab(_booksNT, 39)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gridKitab(List<Map<String, dynamic>> data, int offset) {
    return GridView.builder(
      padding: const EdgeInsets.all(15),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 2.5, mainAxisSpacing: 8, crossAxisSpacing: 8
      ),
      itemCount: data.length,
      itemBuilder: (ctx, i) {
        String name = data[i]['name'] ?? "KITAB";
        int realIndex = offset + i + 1; // Konversi ke urutan 1-66
        
        return ActionChip(
          label: SizedBox(width: double.infinity, child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
          onPressed: () {
            Navigator.pop(ctx);
            setState(() {
              _selectedBookIndex = realIndex;
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
            items: ["TB", "TL"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : _verses.isEmpty 
              ? Center(child: Text("Data tidak ditemukan.\nCoba pilih kitab lain."))
              : ListView.builder(
                  itemCount: _verses.length,
                  padding: const EdgeInsets.all(15),
                  itemBuilder: (ctx, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: "${_verses[i]['verse']}. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 17)),
                      TextSpan(text: "${_verses[i]['text']}", style: const TextStyle(fontSize: 17)),
                    ])),
                  ),
                ),
    );
  }
}