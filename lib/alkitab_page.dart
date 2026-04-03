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
  int _selectedBookId = 1; // ID Kitab (1-66)
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
      
      // Tutup koneksi lama jika ada
      if (_db != null) await _db!.close();
      
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
      final List<Map<String, dynamic>> books = await _db!.query('books', orderBy: 'id ASC');
      List<Map<String, dynamic>> ot = [];
      List<Map<String, dynamic>> nt = [];
      
      for (int i = 0; i < books.length; i++) {
        if (i < 39) ot.add(books[i]); else nt.add(books[i]);
        
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
      
      // Ambil info kolom untuk membedakan TB vs KJV OpenLP
      List<Map<String, dynamic>> colInfo = await _db!.rawQuery("PRAGMA table_info(verses)");
      
      // Cek apakah ini TB (punya kolom book_number) atau KJV (punya kolom book_id)
      bool hasBookNumber = colInfo.any((c) => c['name'] == 'book_number');
      
      String queryTable = 'verses';
      String bCol = hasBookNumber ? 'book_number' : 'book_id';
      String cCol = 'chapter';
      String vCol = hasBookNumber ? 'verse' : 'number';
      String tCol = 'text';

      // JANTUNG MASALAH: 
      // Jika TB: book_number = 10, 20, 30...
      // Jika KJV OpenLP: book_id = 1, 2, 3...
      int queryId = hasBookNumber ? (_selectedBookId * 10) : _selectedBookId;

      debugPrint("Querying: $queryTable WHERE $bCol=$queryId AND $cCol=$_chapter");

      final List<Map<String, dynamic>> result = await _db!.query(
        queryTable,
        where: '$bCol = ? AND $cCol = ?',
        whereArgs: [queryId, _chapter],
        orderBy: '$vCol ASC'
      );

      setState(() {
        _verses = result.map((row) => {
          'number': row[vCol],
          'text': _cleanHtml(row[tCol].toString()),
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Load Verses Error: $e");
      setState(() { _verses = []; _isLoading = false; });
    }
  }

  String _cleanHtml(String html) {
    // OpenLP sering pakai tag {br} atau <br/>
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('{br}', '\n')
        .replaceAll('{I}', '')
        .replaceAll('{/I}', '')
        .trim();
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
            const Padding(padding: EdgeInsets.all(20), child: Text("PILIH KITAB", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
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
    );
  }

  Widget _gridKitab(List<Map<String, dynamic>> data) {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 2.5, mainAxisSpacing: 5, crossAxisSpacing: 5
      ),
      itemCount: data.length,
      itemBuilder: (ctx, i) {
        String name = data[i]['name'] ?? "KITAB";
        int id = data[i]['id'] ?? 1;
        return ActionChip(
          label: SizedBox(width: double.infinity, child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
          onPressed: () {
            Navigator.pop(ctx);
            setState(() {
              _selectedBookId = id;
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
        title: InkWell(
          onTap: _showPicker,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("$_bookName $_chapter", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              const Icon(Icons.arrow_drop_down, color: Colors.blue),
            ],
          ),
        ),
        actions: [
          DropdownButton<String>(
            value: _currentVersion,
            underline: const SizedBox(),
            items: ["TB", "TL", "KJV"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => _currentVersion = v);
                _initDatabase();
              }
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : _verses.isEmpty 
              ? const Center(child: Text("Data tidak ditemukan atau ID salah."))
              : ListView.builder(
                  itemCount: _verses.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (ctx, i) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(color: Colors.black, fontSize: 17, height: 1.6),
                          children: [
                            TextSpan(text: "${_verses[i]['number']}. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                            TextSpan(text: _verses[i]['text']),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}