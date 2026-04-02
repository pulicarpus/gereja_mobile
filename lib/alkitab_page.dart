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

class _AlkitabPageState extends State<AlkitabPage> with SingleTickerProviderStateMixin {
  Database? _db;
  List<Map<String, dynamic>> _verses = [];
  Map<int, String> _pericopes = {};
  List<Map<String, dynamic>> _booksOT = [];
  List<Map<String, dynamic>> _booksNT = [];
  bool _isLoading = true;
  TabController? _tabController;

  // Status Navigasi Default
  String _currentVersion = "TB";
  int _bookId = 1; // ID 1-66 (Normalized)
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
    // Logika load DB Bos yang sudah ada
    setState(() => _isLoading = true);
    var dbPath = await getDatabasesPath();
    String fileName = _bibleFiles[_currentVersion] ?? "TB.SQLite3";
    var path = p.join(dbPath, fileName);

    if (!await databaseExists(path)) {
      await Directory(p.dirname(path)).create(recursive: true);
      ByteData data = await rootBundle.load("assets/$fileName");
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
    }
    _db = await openDatabase(path);
    await _loadBooksGrid();
    await _loadVerses();
  }

  // Load Daftar Kitab dan Pisahkan Perjanjian Lama/Baru
  Future<void> _loadBooksGrid() async {
    if (_db == null) return;
    final List<Map<String, dynamic>> books = await _db!.query('books', orderBy: 'book_number ASC');
    List<Map<String, dynamic>> ot = [];
    List<Map<String, dynamic>> nt = [];

    for (var b in books) {
      int rawId = b['book_number'] ?? b['book_id'];
      // TB pakai kelipatan 10, KJV pakai urutan 1-66. Kita deteksi.
      bool isTBStruktur = (books.any((x) => (x['book_number'] ?? 0) > 66));
      int normId = isTBStruktur ? (rawId / 10).round() : rawId;

      if (normId <= 39) {ot.add(b);} else {nt.add(b);}

      if (normId == _bookId) {
        _bookName = (b['short_name'] ?? b['long_name']).toString().toUpperCase();
      }
    }
    setState(() {
      _booksOT = ot;
      _booksNT = nt;
    });
  }

  // Load Ayat dengan deteksi kolom sakti Bos
  Future<void> _loadVerses() async {
    if (_db == null) return;
    List<Map<String, dynamic>> columnInfo = await _db!.rawQuery("PRAGMA table_info(verses)");
    String bookCol = columnInfo.any((c) => c['name'] == 'book_number') ? 'book_number' : 'book_id';
    String textCol = columnInfo.any((c) => c['name'] == 'text') ? 'text' : 'content';
    int targetId = (bookCol == 'book_number') ? _bookId * 10 : _bookId;

    final List<Map<String, dynamic>> verses = await _db!.query(
        'verses', where: '$bookCol = ? AND chapter = ?', whereArgs: [targetId, _chapter], orderBy: 'verse ASC'
    );
    Map<int, String> storyMap = {};
    try {
      final List<Map<String, dynamic>> stories = await _db!.query('stories', where: '$bookCol = ? AND chapter = ?', whereArgs: [targetId, _chapter]);
      for (var s in stories) {storyMap[s['verse']] = s['title'];}
    } catch (_) {}

    setState(() {
      _verses = verses.map((v) => {'verse': v['verse'], 'text': v[textCol]}).toList();
      _pericopes = storyMap;
      _isLoading = false;
    });
  }

  // ===================== TAMPILAN PICKER (SCREENSHOT 11-13) =====================

  void _showMainNavigation() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // Agar background modal transparans
      builder: (context) => _buildGridPickerModal(),
    );
  }

  Widget _buildGridPickerModal() {
    // Style teks header di modal
    const headerStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header Judul Modal
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text("PILIH KITAB", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
          // TabBar Perjanjian Lama / Perjanjian Baru
          TabBar(
            controller: _tabController,
            labelColor: Colors.pinkAccent,
            unselectedLabelColor: Colors.black54,
            indicatorColor: Colors.pinkAccent,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: const [Tab(text: "PERJANJIAN LAMA"), Tab(text: "PERJANJIAN BARU")],
          ),
          // Isi Tab
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBookGrid(_booksOT), // PL
                _buildBookGrid(_booksNT), // PB
              ],
            ),
          ),
          // Tombol Batal di bawah
          TextButton(
            onTap: () => Navigator.pop(context),
            child: const Text("BATAL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // Grid Abjad Kitab (Screenshot 13)
  Widget _buildBookGrid(List<Map<String, dynamic>> books) {
    return GridView.builder(
      padding: const EdgeInsets.all(15),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.8),
      itemCount: books.length,
      itemBuilder: (context, i) {
        final b = books[i];
        // Ambil short_name untuk abjad (Screenshot 13)
        String sName = (b['short_name'] ?? '').toString().toUpperCase();
        return InkWell(
          onTap: () {
            // Navigator.pop(context); // Tutup picker kitab
            _handleBookSelection(b);
          },
          child: Container(
            decoration: BoxDecoration(color: const Color(0xFFF5F5F7), borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text(sName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87))),
          ),
        );
      },
    );
  }

  Future<void> _handleBookSelection(Map<String, dynamic> bookData) async {
    // Tutup Picker Kitab
    Navigator.pop(context);

    // Ambil info pasal unik dari DB
    int rawId = bookData['book_number'] ?? bookData['book_id'];
    int normBookId = (rawId >= 10) ? (rawId / 10).round() : rawId;
    int targetId = (rawId >= 10) ? normBookId * 10 : normBookId;
    List<Map<String, dynamic>> result = await _db!.rawQuery(
        "SELECT MAX(chapter) as max_chap FROM verses WHERE ${rawId >= 10 ? 'book_number' : 'book_id'} = ?", [targetId]
    );
    int maxChapter = (result.isNotEmpty && result.first['max_chap'] != null) ? result.first['max_chap'] as int : 50;

    // Munculkan Picker Pasal (Screenshot 12)
    _showGridNumberPicker(
      title: "${bookData['long_name']} - PASAL",
      itemCount: maxChapter,
      onSelected: (selectedChapter) {
        setState(() {
          _bookId = normBookId;
          _chapter = selectedChapter;
          _bookName = (bookData['short_name'] ?? bookData['long_name']).toString().toUpperCase();
        });
        _loadVerses();
      },
    );
  }

  // Grid Angka untuk Pasal dan Ayat (Screenshot 11 & 12)
  void _showGridNumberPicker({required String title, required int itemCount, required Function(int) onSelected}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(15),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 10, crossAxisSpacing: 10),
                itemCount: itemCount,
                itemBuilder: (context, i) => InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    onSelected(i + 1);
                  },
                  child: Container(
                    decoration: BoxDecoration(color: const Color(0xFFF5F5F7), borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text("${i + 1}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  ),
                ),
              ),
            ),
            TextButton(onTap: () => Navigator.pop(context), child: const Text("BATAL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // ===================== UI UTAMA =====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.indigo),
        title: InkWell(
          onTap: _showMainNavigation, // Panggil navigasi modern
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("$_bookName $_chapter", style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
              const SizedBox(width: 5),
              const Icon(Icons.arrow_drop_down, color: Colors.indigo),
            ],
          ),
        ),
        actions: [
          DropdownButton<String>(
            value: _currentVersion, dropdownColor: Colors.white, underline: Container(), icon: const Icon(Icons.tune, color: Colors.indigo),
            style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
            onChanged: (v) {if (v != null) {setState(() => _currentVersion = v); _initDatabase();}},
            items: ["TB", "TL", "KJV"].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          ),
          const SizedBox(width: 15),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _verses.length,
              itemBuilder: (context, index) {
                final v = _verses[index];
                final String? perikop = _pericopes[v['verse']];
                // Regex pembersih tag TB Bos (perlu disesuaikan per versi nanti)
                final String cleanText = v['text'].toString().replaceAll(RegExp(r'<[^>]*>'), '').trim();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (perikop != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 25, bottom: 10),
                        child: Text(perikop, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown)),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 17, color: Colors.black87, height: 1.5),
                          children: [
                            TextSpan(text: "${v['verse']}. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                            TextSpan(text: cleanText),
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