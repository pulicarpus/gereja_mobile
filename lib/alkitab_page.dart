import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

class AlkitabPage extends StatefulWidget {
  const AlkitabPage({super.key});

  @override
  State<AlkitabPage> createState() => _AlkitabPageState();
}

class _AlkitabPageState extends State<AlkitabPage> {
  Database? _db;
  List<Map<String, dynamic>> _verses = [];
  List<Map<String, dynamic>> _allBooks = [];
  Map<int, String> _pericopes = {};
  bool _isLoading = true;
  
  Set<int> _selectedVerses = {}; 
  Map<int, String> _userNotes = {};

  String _currentVersion = "TB";
  int _bookId = 10; 
  int _chapter = 1;
  String _bookName = "Kejadian";
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  
  // State untuk filter pencarian
  String _searchScope = "SEMUA"; // SEMUA, PL, PB, KITAB

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  // --- MEMBERSIHKAN TEKS & SINGKATAN NAMA KITAB ---
  String _cleanText(String text) {
    if (text.isEmpty) return "";
    return text.replaceAll(RegExp(r'<[^>]*>|\\f.*?\\f|\\.*?\\'), '').trim();
  }

  String _shortenBookName(String name) {
    // Memotong nama panjang dari database agar rapi di UI
    return name
      .replaceAll(RegExp(r'Surat Paulus (Yang Pertama|Yang Kedua|Kepada|Yang Ketiga) ', caseSensitive: false), '')
      .replaceAll(RegExp(r'Kepada Jemaat Di |Kepada Orang |Dari |Injil Menurut |Kisah Para ', caseSensitive: false), '')
      .trim();
  }

  // --- DATABASE OPS ---
  Future<void> _initDatabase() async {
    try {
      var dbPath = await getDatabasesPath();
      var path = p.join(dbPath, "TB.SQLite3");
      _db = await openDatabase(path);
      await _db!.execute('CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, book_id INTEGER, chapter INTEGER, verse INTEGER, content TEXT, date TEXT)');
      await _loadBooks();
      await _loadData();
    } catch (e) { debugPrint("DB Error: $e"); }
  }

  Future<void> _loadBooks() async {
    final books = await _db!.query('books', orderBy: 'book_number ASC');
    setState(() => _allBooks = books);
  }

  Future<void> _loadData({int? scrollToVerse}) async {
    setState(() => _isLoading = true);
    final verses = await _db!.query('verses', where: 'book_number = ? AND chapter = ?', whereArgs: [_bookId, _chapter]);
    final notes = await _db!.query('notes', where: 'book_id = ? AND chapter = ?', whereArgs: [_bookId, _chapter]);
    
    Map<int, String> tempNotes = {};
    for (var n in notes) { tempNotes[n['verse'] as int] = n['content'] as String; }

    Map<int, String> storyMap = {};
    try {
      final stories = await _db!.query('stories', where: 'book_number = ? AND chapter = ?', whereArgs: [_bookId, _chapter]);
      for (var s in stories) { storyMap[s['verse'] as int] = s['title'] as String; }
    } catch (_) {}

    setState(() {
      _verses = verses;
      _pericopes = storyMap;
      _userNotes = tempNotes;
      _bookName = _allBooks.firstWhere((b) => b['book_number'] == _bookId)['long_name'];
      _isLoading = false;
      _selectedVerses.clear();
    });

    if (scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo((scrollToVerse - 1) * 100.0, duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
      });
    }
  }

  // --- LOGIKA PENCARIAN ADVANCED ---
  Future<List<Map<String, dynamic>>> _searchBible(String query) async {
    if (query.length < 2) return [];
    String whereClause = "v.text LIKE ?";
    List<dynamic> args = ['%$query%'];

    if (_searchScope == "PL") {
      whereClause += " AND v.book_number <= 39";
    } else if (_searchScope == "PB") {
      whereClause += " AND v.book_number > 39";
    } else if (_searchScope == "KITAB") {
      whereClause += " AND v.book_number = ?";
      args.add(_bookId);
    }

    return await _db!.rawQuery('''
      SELECT v.*, b.long_name 
      FROM verses v 
      JOIN books b ON v.book_number = b.book_number 
      WHERE $whereClause
    ''', args); // Batasan LIMIT dihapus sesuai request
  }

  void _showSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setST) => Container(
          height: MediaQuery.of(context).size.height * 0.9,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: "Cari kata...",
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); setST(() {}); }),
                ),
                onChanged: (_) => setST(() {}),
              ),
              const SizedBox(height: 10),
              // Filter Chips PL/PB/Semua
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ["SEMUA", "PL", "PB", "KITAB"].map((scope) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(scope == "KITAB" ? _shortenBookName(_bookName) : scope),
                        selected: _searchScope == scope,
                        onSelected: (bool selected) {
                          if (selected) setST(() => _searchScope = scope);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _searchBible(_searchController.text),
                  builder: (context, snapshot) {
                    if (_searchController.text.isEmpty) return const Center(child: Text("Ketik untuk mencari"));
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final results = snapshot.data!;
                    return Column(
                      children: [
                        Text("Ditemukan ${results.length} hasil", style: const TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(
                          child: ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (context, i) {
                              var res = results[i];
                              return ListTile(
                                title: Text("${_shortenBookName(res['long_name'])} ${res['chapter']}:${res['verse']}", style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
                                subtitle: Text(_cleanText(res['text'])),
                                onTap: () {
                                  Navigator.pop(context);
                                  setState(() { _bookId = res['book_number']; _chapter = res['chapter']; });
                                  _loadData(scrollToVerse: res['verse']);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // --- PICKER TERPISAH PL & PB ---
  void _showTopPicker() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Tutup",
      pageBuilder: (context, a1, a2) => StatefulBuilder(
        builder: (context, setST) => DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.indigo,
              title: const Text("Pilih Kitab"),
              bottom: const TabBar(
                tabs: [Tab(text: "PERJANJIAN LAMA"), Tab(text: "PERJANJIAN BARU")],
                indicatorColor: Colors.white,
              ),
            ),
            body: TabBarView(
              children: [
                _buildGridKitab(_allBooks.where((b) => b['book_number'] <= 39).toList()),
                _buildGridKitab(_allBooks.where((b) => b['book_number'] > 39).toList()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridKitab(List<Map<String, dynamic>> books) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 2.5, mainAxisSpacing: 8, crossAxisSpacing: 8),
      itemCount: books.length,
      itemBuilder: (context, i) => ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black, elevation: 0),
        onPressed: () async {
          int bid = books[i]['book_number'];
          var res = await _db!.rawQuery('SELECT MAX(chapter) as m FROM verses WHERE book_number = ?', [bid]);
          int maxChap = res.first['m'] as int;
          _showChapterPicker(bid, books[i]['long_name'], maxChap);
        },
        child: Text(_shortenBookName(books[i]['long_name']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  void _showChapterPicker(int bid, String bname, int max) {
    showModalBottomSheet(
      context: context,
      builder: (context) => GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 10, crossAxisSpacing: 10),
        itemCount: max,
        itemBuilder: (context, i) => InkWell(
          onTap: () {
            setState(() { _bookId = bid; _chapter = i + 1; });
            _loadData();
            Navigator.pop(context); // Tutup pasal
            Navigator.pop(context); // Tutup kitab
          },
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.indigo[50], borderRadius: BorderRadius.circular(8)),
            child: Text("${i + 1}", style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        title: GestureDetector(
          onTap: _showTopPicker,
          child: Row(children: [Text("${_shortenBookName(_bookName)} $_chapter"), const Icon(Icons.arrow_drop_down)]),
        ),
        actions: [IconButton(icon: const Icon(Icons.search), onPressed: _showSearch)],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _verses.length,
        itemBuilder: (context, i) {
          final v = _verses[i];
          final String? pTitle = _pericopes[v['verse']];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pTitle != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(pTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, color: Colors.brown))),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: RichText(text: TextSpan(style: const TextStyle(fontSize: 18, color: Colors.black87), children: [
                  TextSpan(text: "${v['verse']} ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 14)),
                  TextSpan(text: _cleanText(v['text'])),
                ])),
              ),
            ],
          );
        },
      ),
    );
  }
}