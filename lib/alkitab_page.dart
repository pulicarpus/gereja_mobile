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

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  // --- MEMBERSIHKAN TEKS DARI TAG DATABASE ---
  String _cleanText(String text) {
    if (text.isEmpty) return "";
    return text
        .replaceAll(RegExp(r'<[^>]*>'), '') 
        .replaceAll(RegExp(r'\\f.*?\\f'), '') 
        .replaceAll(RegExp(r'\\.*?\\'), '') 
        .trim();
  }

  String _shortenBookName(String name) {
    return name
      .replaceAll("Surat Paulus Yang Pertama Kepada Jemaat Di ", "1 ")
      .replaceAll("Surat Paulus Yang Kedua Kepada Jemaat Di ", "2 ")
      .replaceAll("Surat Paulus Kepada Jemaat Di ", "")
      .replaceAll("Surat Kepada Orang ", "")
      .replaceAll("Surat Paulus Kepada ", "")
      .replaceAll("Surat Yang Pertama Dari ", "1 ")
      .replaceAll("Surat Yang Kedua Dari ", "2 ")
      .replaceAll("Surat Yang Ketiga Dari ", "3 ")
      .replaceAll("Surat Dari ", "")
      .replaceAll("Injil Menurut ", "")
      .replaceAll("Kisah Para ", "")
      .trim();
  }

  Future<void> _initDatabase() async {
    try {
      setState(() => _isLoading = true);
      var dbPath = await getDatabasesPath();
      String fileName = _currentVersion == "TB" ? "TB.SQLite3" : "TJL.SQLite3";
      var path = p.join(dbPath, fileName);

      if (!(await databaseExists(path))) {
        await Directory(p.dirname(path)).create(recursive: true);
        ByteData data = await rootBundle.load("assets/$fileName");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      }

      _db = await openDatabase(path);
      await _db!.execute('CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, book_id INTEGER, chapter INTEGER, verse INTEGER, content TEXT, date TEXT)');
      
      await _loadBooks();
      await _loadData();
    } catch (e) {
      debugPrint("Error Init: $e");
    }
  }

  Future<void> _loadBooks() async {
    final books = await _db!.query('books', orderBy: 'book_number ASC');
    setState(() => _allBooks = books);
  }

  Future<void> _loadData({int? scrollToVerse}) async {
    setState(() => _isLoading = true);
    final verses = await _db!.query('verses', where: 'book_number = ? AND chapter = ?', whereArgs: [_bookId, _chapter]);
    
    final notesData = await _db!.query('notes', where: 'book_id = ? AND chapter = ?', whereArgs: [_bookId, _chapter]);
    Map<int, String> tempNotes = {};
    for (var n in notesData) { tempNotes[n['verse'] as int] = n['content'] as String; }

    Map<int, String> storyMap = {};
    if (_currentVersion == "TB") {
      try {
        final stories = await _db!.query('stories', where: 'book_number = ? AND chapter = ?', whereArgs: [_bookId, _chapter]);
        for (var s in stories) { 
          storyMap[s['verse'] as int] = s['title'] as String; 
        }
      } catch (_) {}
    }

    setState(() {
      _verses = verses;
      _pericopes = storyMap;
      _userNotes = tempNotes;
      if (_allBooks.isNotEmpty) {
        _bookName = _allBooks.firstWhere((b) => b['book_number'] == _bookId)['long_name'];
      }
      _isLoading = false;
      _selectedVerses.clear();
    });

    if (scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo((scrollToVerse - 1) * 90.0, duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
      });
    }
  }

  // --- LOGIKA HIGHLIGHT KATA (MIRIP SCREENSHOT) ---
  TextSpan _getHighlightedText(String fullText, String query) {
    if (query.isEmpty || !fullText.toLowerCase().contains(query.toLowerCase())) {
      return TextSpan(text: fullText, style: const TextStyle(color: Colors.black87));
    }
    
    List<TextSpan> spans = [];
    int start = 0;
    int indexOfHighlight;
    String loweredFull = fullText.toLowerCase();
    String loweredQuery = query.toLowerCase();

    while ((indexOfHighlight = loweredFull.indexOf(loweredQuery, start)) != -1) {
      if (indexOfHighlight > start) {
        spans.add(TextSpan(text: fullText.substring(start, indexOfHighlight)));
      }
      spans.add(TextSpan(
        text: fullText.substring(indexOfHighlight, indexOfHighlight + query.length),
        style: const TextStyle(backgroundColor: Colors.yellow, fontWeight: FontWeight.bold, color: Colors.black),
      ));
      start = indexOfHighlight + query.length;
    }
    
    if (start < fullText.length) {
      spans.add(TextSpan(text: fullText.substring(start)));
    }

    return TextSpan(children: spans, style: const TextStyle(color: Colors.black87, fontSize: 14));
  }

  // --- FITUR PENCARIAN (BOTTOM SHEET MODIFIED) ---
  void _showSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setST) => Container(
          height: MediaQuery.of(context).size.height * 0.9,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 15),
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: "Cari ayat...",
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); setST(() {}); }),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (val) => setST(() {}),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _searchBible(_searchController.text),
                  builder: (context, snapshot) {
                    if (_searchController.text.isEmpty) return const Center(child: Text("Ketik kata yang ingin dicari"));
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    
                    final results = snapshot.data!;
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text("Ditemukan ${results.length} hasil", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                        ),
                        Expanded(
                          child: ListView.separated(
                            itemCount: results.length,
                            separatorBuilder: (context, i) => const Divider(),
                            itemBuilder: (context, i) {
                              var res = results[i];
                              String cleaned = _cleanText(res['text'] as String);
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  "${_shortenBookName(res['long_name'] as String)} ${res['chapter']}:${res['verse']}",
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                                ),
                                subtitle: RichText(
                                  text: _getHighlightedText(cleaned, _searchController.text),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  setState(() {
                                    _bookId = res['book_number'] as int;
                                    _chapter = res['chapter'] as int;
                                  });
                                  _loadData(scrollToVerse: res['verse'] as int);
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

  Future<List<Map<String, dynamic>>> _searchBible(String query) async {
    if (query.length < 2) return [];
    return await _db!.rawQuery('''
      SELECT v.*, b.long_name 
      FROM verses v 
      JOIN books b ON v.book_number = b.book_number 
      WHERE v.text LIKE ? 
      LIMIT 100
    ''', ['%$query%']);
  }

  // --- UI PICKER & APPBAR ---
  void _showTopPicker() async {
    int tempBookId = _bookId;
    int currentStep = 0; 
    
    Future<int> _getMax(String col, int bid, [int? chap]) async {
      String q = chap == null ? 'SELECT MAX($col) as m FROM verses WHERE book_number = ?' : 'SELECT MAX($col) as m FROM verses WHERE book_number = ? AND chapter = ?';
      var r = await _db!.rawQuery(q, chap == null ? [bid] : [bid, chap]);
      return r.first['m'] as int? ?? 1;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Tutup",
      pageBuilder: (context, a1, a2) => StatefulBuilder(
        builder: (context, setST) => Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.indigo,
            title: Text(currentStep == 0 ? "Pilih Kitab" : "Pilih Pasal"),
            leading: IconButton(icon: Icon(currentStep == 0 ? Icons.close : Icons.arrow_back), onPressed: () => currentStep == 0 ? Navigator.pop(context) : setST(() => currentStep = 0)),
          ),
          body: currentStep == 0 
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text("PERJANJIAN LAMA", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  _gridKitab(_allBooks.where((b) => (b['book_number'] as int) <= 39).toList(), (id) async {
                    tempBookId = id;
                    setST(() => currentStep = 1);
                  }),
                  const SizedBox(height: 20),
                  const Text("PERJANJIAN BARU", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  _gridKitab(_allBooks.where((b) => (b['book_number'] as int) > 39).toList(), (id) async {
                    tempBookId = id;
                    setST(() => currentStep = 1);
                  }),
                ],
              )
            : FutureBuilder<int>(
                future: _getMax('chapter', tempBookId),
                builder: (context, snap) => GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 10, crossAxisSpacing: 10),
                  itemCount: snap.data ?? 0,
                  itemBuilder: (context, i) => InkWell(
                    onTap: () {
                      setState(() { _bookId = tempBookId; _chapter = i + 1; });
                      _loadData();
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      alignment: Alignment.center,
                      child: Text("${i + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                    ),
                  ),
                ),
              ),
        ),
      ),
      transitionBuilder: (context, a1, a2, child) => SlideTransition(position: Tween(begin: const Offset(0, -1), end: const Offset(0, 0)).animate(a1), child: child),
    );
  }

  Widget _gridKitab(List<Map<String, dynamic>> books, Function(int) onSelect) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 2.5, mainAxisSpacing: 8, crossAxisSpacing: 8),
      itemCount: books.length,
      itemBuilder: (context, i) => InkWell(
        onTap: () => onSelect(books[i]['book_number'] as int),
        child: Container(
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
          alignment: Alignment.center,
          child: Text(_shortenBookName(books[i]['long_name'] as String), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("${_shortenBookName(_bookName)} $_chapter"),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _showSearch),
          if (_selectedVerses.isNotEmpty)
            IconButton(icon: const Icon(Icons.copy), onPressed: () {
              String copyText = _selectedVerses.map((idx) => "${idx+1}. ${_cleanText(_verses[idx]['text'] as String)}").join("\n");
              Clipboard.setData(ClipboardData(text: copyText));
              setState(() => _selectedVerses.clear());
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Disalin")));
            }),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _verses.length,
            itemBuilder: (context, i) {
              final v = _verses[i];
              final int vNum = v['verse'] as int;
              final String? pTitle = _pericopes[vNum];
              bool isSelected = _selectedVerses.contains(i);

              return GestureDetector(
                onLongPress: () => setState(() => _selectedVerses.add(i)),
                onTap: () => setState(() => isSelected ? _selectedVerses.remove(i) : (_selectedVerses.isNotEmpty ? _selectedVerses.add(i) : null)),
                child: Container(
                  color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (pTitle != null && _currentVersion == "TB")
                        Padding(
                          padding: const EdgeInsets.only(top: 15, bottom: 5),
                          child: Text(pTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, color: Colors.brown)),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.6),
                            children: [
                              TextSpan(text: "$vNum ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 14)),
                              TextSpan(text: _cleanText(v['text'] as String)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }
}