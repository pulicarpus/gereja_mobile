import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart'; // Tambahkan plugin ini di pubspec.yaml

class AlkitabPage extends StatefulWidget {
  const AlkitabPage({super.key});

  @override
  State<AlkitabPage> createState() => _AlkitabPageState();
}

class _AlkitabPageState extends State<AlkitabPage> {
  Database? _db;
  List<Map<String, dynamic>> _verses = [];
  List<Map<String, dynamic>> _allBooks = [];
  List<int> _selectedVerses = [];
  
  bool _isLoading = true;
  double _textSize = 18.0;
  String _currentVersion = "TB"; // TB atau TJL
  
  int _bookId = 10; // Default Kejadian
  int _chapter = 1;
  String _bookName = "Kejadian";

  final ScrollController _scrollController = ScrollController();
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    _prefs = await SharedPreferences.getInstance();
    _textSize = _prefs.getDouble('text_size') ?? 18.0;
    await _initDatabase();
  }

  // --- LOGIKA DATABASE ---
  Future<void> _initDatabase() async {
    setState(() => _isLoading = true);
    var dbPath = await getDatabasesPath();
    String fileName = "$_currentVersion.SQLite3"; 
    var path = p.join(dbPath, fileName);

    if (!(await databaseExists(path))) {
      ByteData data = await rootBundle.load("assets/$fileName");
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
    }

    if (_db != null) await _db!.close();
    _db = await openDatabase(path);
    await _loadBooks();
    await _loadContent();
  }

  Future<void> _loadBooks() async {
    final books = await _db!.query('books', orderBy: 'book_number ASC');
    setState(() => _allBooks = books);
  }

  Future<void> _loadContent({int? scrollToVerse}) async {
    final verses = await _db!.query('verses', 
        where: 'book_number = ? AND chapter = ?', 
        whereArgs: [_bookId, _chapter]);

    setState(() {
      _verses = verses;
      _bookName = _allBooks.firstWhere((b) => b['book_number'] == _bookId)['long_name'];
      _isLoading = false;
      _selectedVerses.clear();
    });

    if (scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo((scrollToVerse - 1) * 80.0, 
            duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
      });
    }
  }

  // --- SINGKATAN SABDA (Persis Kode Kotlin Bos) ---
  String _getAbbr(String name) {
    int idx = _allBooks.indexWhere((b) => b['long_name'] == name);
    List<String> sabs = [
      "KEJ", "KEL", "IMA", "BIL", "ULA", "YOS", "HAK", "RUT", "1SAM", "2SAM", "1RAJ", "2RAJ", "1TAW", "2TAW", "EZR", "NEH", "EST", "AYU", "MAZ", "AMS", "PKH", "KID", "YES", "YER", "RAT", "YEH", "DAN", "HOS", "YOE", "AMO", "OBA", "YUN", "MIK", "NAH", "HAB", "ZEF", "HAG", "ZAK", "MAL",
      "MAT", "MAR", "LUK", "YOH", "KIS", "ROM", "1KOR", "2KOR", "GAL", "EFE", "FIL", "KOL", "1TES", "2TES", "1TIM", "2TIM", "TIT", "FLM", "IBR", "YAK", "1PET", "2PET", "1YOH", "2YOH", "3YOH", "YUD", "WAH"
    ];
    return (idx >= 0 && idx < sabs.length) ? sabs[idx] : name.substring(0, 3).toUpperCase();
  }

  // --- UI DIALOG NAVIGASI (Flexbox Style) ---
  void _showSelectionDialog() {
    int step = 0; // 0: Kitab, 1: Pasal, 2: Ayat
    int? tId; String tName = ""; int? tChap; int mChap = 0; int mVer = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setST) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(step == 0 ? "PILIH KITAB" : (step == 1 ? "${tName.toUpperCase()} - PASAL" : "${tName.toUpperCase()} $tChap - AYAT"),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 20),
              Expanded(
                child: step == 0 
                  ? _buildBookSelector(setST, (id, name) async {
                      tId = id; tName = name;
                      var res = await _db!.rawQuery('SELECT MAX(chapter) as m FROM verses WHERE book_number = ?', [id]);
                      mChap = res.first['m'] as int;
                      setST(() => step = 1);
                    })
                  : (step == 1 
                      ? _buildGrid(mChap, (val) async {
                          tChap = val;
                          var res = await _db!.rawQuery('SELECT MAX(verse) as m FROM verses WHERE book_number = ? AND chapter = ?', [tId, val]);
                          mVer = res.first['m'] as int;
                          setST(() => step = 2);
                        })
                      : _buildGrid(mVer, (val) {
                          setState(() { _bookId = tId!; _chapter = tChap!; });
                          _loadContent(scrollToVerse: val);
                          Navigator.pop(context);
                        })
                    ),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("BATAL", style: TextStyle(color: Colors.grey))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookSelector(StateSetter setST, Function(int, String) onSelect) {
    var pl = _allBooks.where((b) => (b['book_number'] as int) <= 39).toList();
    var pb = _allBooks.where((b) => (b['book_number'] as int) >= 40).toList();
    return ListView(
      children: [
        _header("PERJANJIAN LAMA", Colors.pink),
        _gridBooks(pl, Colors.pink, onSelect),
        const SizedBox(height: 20),
        _header("PERJANJIAN BARU", Colors.blue),
        _gridBooks(pb, Colors.blue, onSelect),
      ],
    );
  }

  Widget _header(String t, Color c) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 10)));

  Widget _gridBooks(List<Map<String, dynamic>> list, Color c, Function(int, String) onSelect) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: list.map((b) => InkWell(
        onTap: () => onSelect(b['book_number'], b['long_name']),
        child: Container(
          width: (MediaQuery.of(context).size.width - 72) / 5,
          height: 40,
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Text(_getAbbr(b['long_name']), style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 11)),
        ),
      )).toList(),
    );
  }

  Widget _buildGrid(int count, Function(int) onSelect) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 8, crossAxisSpacing: 8),
      itemCount: count,
      itemBuilder: (context, i) => InkWell(
        onTap: () => onSelect(i + 1),
        child: Container(
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center, child: Text("${i + 1}", style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  // --- ACTION MODE (Salin & Bagikan) ---
  void _handleAction(String type) {
    String output = "$_bookName $_chapter:${_selectedVerses.join(",")}\n\n";
    for (var i in _selectedVerses) {
      output += "$i. ${_verses.firstWhere((v) => v['verse'] == i)['text']}\n";
    }
    if (type == "SALIN") {
      Clipboard.setData(ClipboardData(text: output));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Disalin ke Clipboard")));
    } else {
      Share.share(output);
    }
    setState(() => _selectedVerses.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo, foregroundColor: Colors.white,
        title: GestureDetector(
          onTap: _showSelectionDialog,
          child: Row(children: [Text("$_bookName $_chapter"), const Icon(Icons.arrow_drop_down)]),
        ),
        actions: [
          // SPINNER VERSI (TB / TJL)
          PopupMenuButton<String>(
            initialValue: _currentVersion,
            onSelected: (v) { setState(() => _currentVersion = v); _initDatabase(); },
            itemBuilder: (context) => [
              const PopupMenuItem(value: "TB", child: Text("Terjemahan Baru (TB)")),
              const PopupMenuItem(value: "TJL", child: Text("Terjemahan Lama (TJL)")),
            ],
            child: Padding(padding: const EdgeInsets.all(16), child: Text(_currentVersion, style: const TextStyle(fontWeight: FontWeight.bold))),
          ),
        ],
      ),
      // PINCH TO ZOOM (GestureDetector)
      body: GestureDetector(
        onScaleUpdate: (details) {
          setState(() {
            _textSize = (18.0 * details.scale).clamp(12.0, 40.0);
            _prefs.setDouble('text_size', _textSize);
          });
        },
        child: _isLoading ? const Center(child: CircularProgressIndicator()) : Stack(
          children: [
            ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              itemCount: _verses.length,
              itemBuilder: (context, i) {
                final v = _verses[i];
                final int verseNum = v['verse'];
                final bool isSelected = _selectedVerses.contains(verseNum);
                final String noteKey = "Note_${_bookName.replaceAll(" ", "_")}_${_chapter}_$verseNum";
                final bool hasNote = _prefs.getKeys().any((k) => k.startsWith(noteKey));

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) _selectedVerses.remove(verseNum);
                      else _selectedVerses.add(verseNum);
                    });
                  },
                  child: Container(
                    color: isSelected ? Colors.blue[50] : Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: _textSize, color: Colors.black87, height: 1.5),
                        children: [
                          TextSpan(text: "$verseNum. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14)),
                          TextSpan(text: v['text'].toString().replaceAll(RegExp(r'<[^>]*>'), '')),
                          if (hasNote) const TextSpan(text: " 📝", style: TextStyle(fontSize: 18)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            // Floating Action Bar kalau ada yang dipilih (Persis ActionMode Kotlin)
            if (_selectedVerses.isNotEmpty) Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                color: Colors.indigo[700],
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => _selectedVerses.clear())),
                    Text("${_selectedVerses.length} dipilih", style: const TextStyle(color: Colors.white)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.copy, color: Colors.white), onPressed: () => _handleAction("SALIN")),
                    IconButton(icon: const Icon(Icons.share, color: Colors.white), onPressed: () => _handleAction("BAGIKAN")),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}