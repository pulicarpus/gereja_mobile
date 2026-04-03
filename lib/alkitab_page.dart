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

class _AlkitabPageState extends State<AlkitabPage> {
  Database? _db;
  List<Map<String, dynamic>> _verses = [];
  List<Map<String, dynamic>> _allBooks = [];
  Map<int, String> _pericopes = {};
  bool _isLoading = true;

  // State Navigasi
  int _bookId = 10; // Default Kejadian
  int _chapter = 1;
  String _bookName = "Kejadian";
  String _currentVersion = "TB";
  
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchScope = "SEMUA"; 

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  // --- DATABASE LOGIC ---
  Future<void> _initDatabase() async {
    try {
      var dbPath = await getDatabasesPath();
      var path = p.join(dbPath, "TB.SQLite3");
      
      if (!(await databaseExists(path))) {
        ByteData data = await rootBundle.load("assets/TB.SQLite3");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      }

      _db = await openDatabase(path);
      await _loadBooks();
      await _loadData();
    } catch (e) {
      debugPrint("Error DB: $e");
    }
  }

  Future<void> _loadBooks() async {
    final books = await _db!.query('books', orderBy: 'book_number ASC');
    setState(() => _allBooks = books);
  }

  Future<void> _loadData({int? scrollToVerse}) async {
    setState(() => _isLoading = true);
    final verses = await _db!.query('verses', 
        where: 'book_number = ? AND chapter = ?', 
        whereArgs: [_bookId, _chapter]);

    Map<int, String> storyMap = {};
    try {
      final stories = await _db!.query('stories', 
          where: 'book_number = ? AND chapter = ?', 
          whereArgs: [_bookId, _chapter]);
      for (var s in stories) { 
        storyMap[s['verse'] as int] = s['title'] as String; 
      }
    } catch (_) {}

    setState(() {
      _verses = verses;
      _pericopes = storyMap;
      _bookName = _allBooks.firstWhere((b) => b['book_number'] == _bookId)['long_name'];
      _isLoading = false;
    });

    if (scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Estimasi tinggi item 90.0 agar pas ke ayat tujuan
        _scrollController.animateTo((scrollToVerse - 1) * 90.0, 
            duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
      });
    }
  }

  // --- UTILS ---
  String _cleanText(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>|\\f.*?\\f|\\.*?\\'), '').trim();
  }

  String _abbr(String name) {
    if (name.length <= 4) return name.toUpperCase();
    return name.substring(0, 3).toUpperCase();
  }

  // --- FITUR PENCARIAN (HIGHLIGHT & FILTER) ---
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
                  hintText: "Cari kata kunci...",
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(icon: const Icon(Icons.clear), 
                      onPressed: () { _searchController.clear(); setST(() {}); }),
                ),
                onChanged: (_) => setST(() {}),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ["SEMUA", "PL", "PB", "KITAB"].map((scope) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(scope == "KITAB" ? _abbr(_bookName) : scope),
                      selected: _searchScope == scope,
                      onSelected: (selected) { if (selected) setST(() => _searchScope = scope); },
                    ),
                  )).toList(),
                ),
              ),
              const Divider(),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _searchBible(_searchController.text),
                  builder: (context, snapshot) {
                    if (_searchController.text.isEmpty) return const Center(child: Text("Hasil akan muncul di sini..."));
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final results = snapshot.data!;
                    return ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        var res = results[i];
                        return ListTile(
                          title: Text("${_abbr(res['long_name'])} ${res['chapter']}:${res['verse']}", 
                              style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
                          subtitle: _highlightedWidget(_cleanText(res['text']), _searchController.text),
                          onTap: () {
                            Navigator.pop(context);
                            setState(() { _bookId = res['book_number']; _chapter = res['chapter']; });
                            _loadData(scrollToVerse: res['verse']);
                          },
                        );
                      },
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
    if (query.length < 3) return [];
    String where = "v.text LIKE ?";
    List<dynamic> args = ['%$query%'];
    if (_searchScope == "PL") where += " AND v.book_number <= 39";
    if (_searchScope == "PB") where += " AND v.book_number >= 40";
    if (_searchScope == "KITAB") { where += " AND v.book_number = ?"; args.add(_bookId); }

    return await _db!.rawQuery('SELECT v.*, b.long_name FROM verses v JOIN books b ON v.book_number = b.book_number WHERE $where', args);
  }

  Widget _highlightedWidget(String text, String query) {
    if (query.isEmpty || !text.toLowerCase().contains(query.toLowerCase())) return Text(text);
    List<TextSpan> spans = [];
    int start = 0;
    int indexOfHighlight;
    while ((indexOfHighlight = text.toLowerCase().indexOf(query.toLowerCase(), start)) != -1) {
      if (indexOfHighlight > start) spans.add(TextSpan(text: text.substring(start, indexOfHighlight)));
      spans.add(TextSpan(text: text.substring(indexOfHighlight, indexOfHighlight + query.length), 
          style: const TextStyle(backgroundColor: Colors.yellow, color: Colors.black, fontWeight: FontWeight.bold)));
      start = indexOfHighlight + query.length;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
    return RichText(text: TextSpan(style: const TextStyle(color: Colors.black87), children: spans));
  }

  // --- ALUR PEMILIH (KITAB > PASAL > AYAT) ---
  void _showBiblePicker() {
    int currentStep = 0; // 0: Kitab, 1: Pasal, 2: Ayat
    int? tempBookId;
    String tempBookName = "";
    int? tempChapter;
    int maxChap = 0;
    int maxVerse = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setST) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(currentStep == 0 ? "PILIH KITAB" : (currentStep == 1 ? "$tempBookName - PASAL" : "$tempBookName $tempChapter - AYAT"),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 15),
              Expanded(
                child: currentStep == 0 
                  ? _buildBookList(setST, (id, name) async {
                      tempBookId = id; tempBookName = name;
                      var res = await _db!.rawQuery('SELECT MAX(chapter) as m FROM verses WHERE book_number = ?', [id]);
                      maxChap = res.first['m'] as int;
                      setST(() => currentStep = 1);
                    })
                  : (currentStep == 1 
                      ? _buildGrid(maxChap, (val) async {
                          tempChapter = val;
                          var res = await _db!.rawQuery('SELECT MAX(verse) as m FROM verses WHERE book_number = ? AND chapter = ?', [tempBookId, val]);
                          maxVerse = res.first['m'] as int;
                          setST(() => currentStep = 2);
                        })
                      : _buildGrid(maxVerse, (val) {
                          setState(() { _bookId = tempBookId!; _chapter = tempChapter!; });
                          _loadData(scrollToVerse: val);
                          Navigator.pop(context);
                        })
                    ),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("BATAL")),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookList(StateSetter setST, Function(int, String) onSelect) {
    var pl = _allBooks.where((b) => (b['book_number'] as int) <= 39).toList();
    var pb = _allBooks.where((b) => (b['book_number'] as int) >= 40).toList();
    return ListView(
      children: [
        const Text("PERJANJIAN LAMA", style: TextStyle(color: Colors.pink, fontWeight: FontWeight.bold, fontSize: 11)),
        _bookGrid(pl, Colors.pink, onSelect),
        const SizedBox(height: 20),
        const Text("PERJANJIAN BARU", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11)),
        _bookGrid(pb, Colors.blue, onSelect),
      ],
    );
  }

  Widget _bookGrid(List<Map<String, dynamic>> books, Color color, Function(int, String) onSelect) {
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, childAspectRatio: 2, mainAxisSpacing: 8, crossAxisSpacing: 8),
      itemCount: books.length,
      itemBuilder: (context, i) => InkWell(
        onTap: () => onSelect(books[i]['book_number'], books[i]['long_name']),
        child: Container(
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(5)),
          alignment: Alignment.center,
          child: Text(_abbr(books[i]['long_name']), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
        ),
      ),
    );
  }

  Widget _buildGrid(int count, Function(int) onSelect) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 10, crossAxisSpacing: 10),
      itemCount: count,
      itemBuilder: (context, i) => InkWell(
        onTap: () => onSelect(i + 1),
        child: Container(
          decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(5)),
          alignment: Alignment.center, child: Text("${i + 1}"),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo, foregroundColor: Colors.white,
        title: GestureDetector(
          onTap: _showBiblePicker,
          child: Row(children: [Text("${_abbr(_bookName)} $_chapter"), const Icon(Icons.arrow_drop_down)]),
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
              if (pTitle != null) Padding(padding: const EdgeInsets.only(top: 15, bottom: 5), 
                  child: Text(pTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, color: Colors.brown))),
              Padding(padding: const EdgeInsets.symmetric(vertical: 6), 
                child: RichText(text: TextSpan(style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.6), children: [
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