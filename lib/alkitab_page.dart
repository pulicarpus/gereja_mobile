import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

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
  String _currentVersion = "TB"; 
  
  int _bookId = 10; 
  int _chapter = 1;
  String _displayName = "Kejadian"; // Nama yang tampil di UI

  final ScrollController _scrollController = ScrollController();
  late SharedPreferences _prefs;

  // --- MAPPING NAMA KITAB ALA SABDA/YUKU ---
  // Kita petakan berdasarkan urutan index (0-65) agar pasti akurat
  final List<String> _sabdaNames = [
    "Kejadian", "Keluaran", "Imamat", "Bilangan", "Ulangan", "Yosua", "Hakim-hakim", "Rut", "1 Samuel", "2 Samuel", 
    "1 Raja-raja", "2 Raja-raja", "1 Tawarikh", "2 Tawarikh", "Ezra", "Nehemia", "Ester", "Ayub", "Mazmur", "Amsal", 
    "Pengkhotbah", "Kidung Agung", "Yesaya", "Yeremia", "Ratapan", "Yehezkiel", "Daniel", "Hosea", "Yoel", "Amos", 
    "Obaja", "Yunus", "Mikha", "Nahum", "Habakuk", "Zefanya", "Hagai", "Zakharia", "Maleakhi",
    "Matius", "Markus", "Lukas", "Yohanes", "Kisah Para Rasul", "Roma", "1 Korintus", "2 Korintus", "Galatia", "Efesus", 
    "Filipi", "Kolose", "1 Tesalonika", "2 Tesalonika", "1 Timotius", "2 Timotius", "Titus", "Filemon", "Ibrani", "Yakobus", 
    "1 Petrus", "2 Petrus", "1 Yohanes", "2 Yohanes", "3 Yohanes", "Yudas", "Wahyu"
  ];

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

  Future<void> _initDatabase() async {
    setState(() => _isLoading = true);
    var dbPath = await getDatabasesPath();
    String fileName = "$_currentVersion.SQLite3";
    var path = p.join(dbPath, fileName);

    if (!(await databaseExists(path))) {
      try {
        ByteData data = await rootBundle.load("assets/$fileName");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      } catch (e) { debugPrint("DB Load Error: $e"); }
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

    // Cari index kitab saat ini untuk ambil nama dari _sabdaNames
    int bookIndex = _allBooks.indexWhere((b) => b['book_number'] == _bookId);
    
    setState(() {
      _verses = verses;
      // Gunakan nama dari mapping kita, jika tidak ketemu baru pakai dari DB
      _displayName = (bookIndex >= 0 && bookIndex < _sabdaNames.length) 
          ? _sabdaNames[bookIndex] 
          : _allBooks[bookIndex]['long_name'];
      _isLoading = false;
      _selectedVerses.clear();
    });

    if (scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.jumpTo((scrollToVerse - 1) * 70.0);
      });
    }
  }

  // --- UI DIALOG ---
  void _showSelectionDialog() {
    int step = 0; 
    int? tId; String tName = ""; int? tChap; int mChap = 0; int mVer = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setST) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(step == 0 ? "PILIH KITAB" : (step == 1 ? "${tName.toUpperCase()} - PASAL" : "${tName.toUpperCase()} $tChap - AYAT"),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 20),
              Expanded(
                child: step == 0 ? _buildBookSelector(setST, (id, name) async {
                      tId = id; tName = name;
                      var res = await _db!.rawQuery('SELECT MAX(chapter) as m FROM verses WHERE book_number = ?', [id]);
                      mChap = res.first['m'] as int;
                      setST(() => step = 1);
                    }) : (step == 1 ? _buildNumberGrid(mChap, (val) async {
                          tChap = val;
                          var res = await _db!.rawQuery('SELECT MAX(verse) as m FROM verses WHERE book_number = ? AND chapter = ?', [tId, val]);
                          mVer = res.first['m'] as int;
                          setST(() => step = 2);
                        }) : _buildNumberGrid(mVer, (val) {
                          setState(() { _bookId = tId!; _chapter = tChap!; });
                          _loadContent(scrollToVerse: val);
                          Navigator.pop(context);
                        })),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("BATAL")),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookSelector(StateSetter setST, Function(int, String) onSelect) {
    return ListView(
      children: [
        _sectionLabel("PERJANJIAN LAMA", Colors.pink[300]!),
        _gridBooks(0, 39, Colors.pink[300]!, onSelect),
        const SizedBox(height: 30),
        _sectionLabel("PERJANJIAN BARU", Colors.blue[300]!),
        _gridBooks(39, 66, Colors.blue[300]!, onSelect),
      ],
    );
  }

  Widget _sectionLabel(String t, Color c) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 11)));

  Widget _gridBooks(int start, int end, Color c, Function(int, String) onSelect) {
    // Kita ambil potongan dari list _allBooks
    List<Map<String, dynamic>> slice = _allBooks.sublist(start, end);
    return Wrap(
      spacing: 7, runSpacing: 7,
      children: slice.asMap().entries.map((entry) {
        int localIdx = entry.key;
        var book = entry.value;
        String shortName = _sabdaNames[start + localIdx]; // Ambil nama pendek dari mapping

        return InkWell(
          onTap: () => onSelect(book['book_number'], shortName),
          child: Container(
            width: (MediaQuery.of(context).size.width - 70) / 5,
            height: 40,
            decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey[200]!)),
            alignment: Alignment.center,
            child: Text(shortName.length > 5 ? shortName.substring(0, 5) : shortName, 
                textAlign: TextAlign.center,
                style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 9)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildNumberGrid(int count, Function(int) onSelect) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 10, crossAxisSpacing: 10),
      itemCount: count,
      itemBuilder: (context, i) => InkWell(
        onTap: () => onSelect(i + 1),
        child: Container(
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center, child: Text("${i + 1}"),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo[800], foregroundColor: Colors.white,
        title: GestureDetector(
          onTap: _showSelectionDialog,
          child: Row(children: [Text("$_displayName $_chapter"), const Icon(Icons.arrow_drop_down)]),
        ),
        actions: [
          IconButton(
            icon: Text(_currentVersion, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            onPressed: () {
              setState(() => _currentVersion = (_currentVersion == "TB" ? "TJL" : "TB"));
              _initDatabase();
            },
          )
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : GestureDetector(
        onScaleUpdate: (d) => setState(() { _textSize = (18.0 * d.scale).clamp(12.0, 45.0); }),
        child: Stack(
          children: [
            ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              itemCount: _verses.length,
              itemBuilder: (context, i) {
                final v = _verses[i];
                final bool isSelected = _selectedVerses.contains(v['verse']);
                return InkWell(
                  onTap: () => setState(() { isSelected ? _selectedVerses.remove(v['verse']) : _selectedVerses.add(v['verse']); }),
                  child: Container(
                    color: isSelected ? Colors.indigo[50] : Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: _textSize, color: Colors.black87, height: 1.6),
                        children: [
                          TextSpan(text: "${v['verse']}. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                          TextSpan(text: v['text'].toString().replaceAll(RegExp(r'<[^>]*>'), '')),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_selectedVerses.isNotEmpty) Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                color: Colors.indigo[900],
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => _selectedVerses.clear())),
                    Text("${_selectedVerses.length} dipilih", style: const TextStyle(color: Colors.white)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.copy, color: Colors.white), onPressed: () {
                      _selectedVerses.sort();
                      String txt = "$_displayName $_chapter:${_selectedVerses.join(",")}\n";
                      for(var n in _selectedVerses) txt += "$n. ${_verses.firstWhere((e) => e['verse'] == n)['text']}\n";
                      Clipboard.setData(ClipboardData(text: txt));
                      setState(() => _selectedVerses.clear());
                    }),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}