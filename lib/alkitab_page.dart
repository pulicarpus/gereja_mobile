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
  
  int _bookId = 10; // Default Kejadian
  int _chapter = 1;
  String _displayName = "Kejadian"; 

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

  // --- MEMBERSIHKAN TEKS DARI TAG DATABASE ---
  String _cleanText(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>|\\f.*?\\f|\\.*?\\'), '').trim();
  }

  // --- LOGIKA SINGKATAN ALA SABDA/YUKU (PERSIS VIDEO/DEMO BOS) ---
  String _getShortAbbr(String longName) {
    Map<String, String> abbrMap = {
      // Perjanjian Lama
      "Kejadian": "KEJ", "Keluaran": "KEL", "Imamat": "IMA", "Bilangan": "BIL", "Ulangan": "ULA",
      "Yosua": "YOS", "Hakim-hakim": "HAK", "Rut": "RUT", "1 Samuel": "1SAM", "2 Samuel": "2SAM",
      "1 Raja-raja": "1RAJ", "2 Raja-raja": "2RAJ", "1 Tawarikh": "1TAW", "2 Tawarikh": "2TAW",
      "Ezra": "EZR", "Nehemia": "NEH", "Ester": "EST", "Ayub": "AYU", "Mazmur": "MAZ",
      "Amsal": "AMS", "Pengkhotbah": "PKH", "Kidung Agung": "KID", "Yesaya": "YES",
      "Yeremia": "YER", "Ratapan": "RAT", "Yehezkiel": "YEH", "Daniel": "DAN", "Hosea": "HOS",
      "Yoel": "YOE", "Amos": "AMO", "Obaja": "OBA", "Yunus": "YUN", "Mikha": "MIK",
      "Nahum": "NAH", "Habakuk": "HAB", "Zefanya": "ZEF", "Hagai": "HAG", "Zakharia": "ZAK",
      "Maleakhi": "MAL",
      // Perjanjian Baru
      "Matius": "MAT", "Markus": "MAR", "Lukas": "LUK", "Yohanes": "YOH", "Kisah Para Rasul": "KIS",
      "Roma": "ROM", "1 Korintus": "1KOR", "2 Korintus": "2KOR", "Galatia": "GAL", "Efesus": "EFE",
      "Filipi": "FIL", "Kolose": "KOL", "1 Tesalonika": "1TES", "2 Tesalonika": "2TES",
      "1 Timotius": "1TIM", "2 Timotius": "2TIM", "Titus": "TIT", "Filemon": "FLM", "Ibrani": "IBR",
      "Yakobus": "YAK", "1 Petrus": "1PET", "2 Petrus": "2PET", "1 Yohanes": "1YOH", "2 Yohanes": "2YOH",
      "3 Yohanes": "3YOH", "Yudas": "YUD", "Wahyu": "WAH"
    };
    return abbrMap[longName] ?? (longName.length > 3 ? longName.substring(0, 3).toUpperCase() : longName.toUpperCase());
  }

  // --- DATABASE LOGIC ---
  Future<void> _initDatabase() async {
    setState(() => _isLoading = true);
    var dbPath = await getDatabasesPath();
    String fileName = "$_currentVersion.SQLite3"; // TB.SQLite3 atau TJL.SQLite3
    var path = p.join(dbPath, fileName);

    if (!(await databaseExists(path))) {
      try {
        ByteData data = await rootBundle.load("assets/$fileName");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      } catch (e) {
        debugPrint("Error loading assets/$fileName: $e");
      }
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
      _displayName = _allBooks.firstWhere((b) => b['book_number'] == _bookId)['long_name'];
      _isLoading = false;
      _selectedVerses.clear();
    });

    if (scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo((scrollToVerse - 1) * 85.0, 
            duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
      });
    }
  }

  // --- UI DIALOG NAVIGASI MODERN (FULL-SCREEN, TOP SLIDE, CONSISTENT GRID) ---
  void _showSelectionDialog() {
    int currentStep = 0; // 0: Kitab, 1: Pasal, 2: Ayat
    int? tId; String tName = ""; int? tChap; int maxChap = 0; int maxVerse = 0;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Tutup",
      pageBuilder: (context, a1, a2) => StatefulBuilder(
        builder: (context, setST) => Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.9,
              width: MediaQuery.of(context).size.width,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Text(currentStep == 0 ? "PILIH KITAB" : (currentStep == 1 ? "${tName.toUpperCase()} - PASAL" : "${tName.toUpperCase()} $tChap - AYAT"),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13, letterSpacing: 1.1)),
                  const SizedBox(height: 20),
                  Expanded(
                    child: currentStep == 0 
                      ? _buildBookSelector(setST, (id, name) async {
                          tId = id; tName = name;
                          var res = await _db!.rawQuery('SELECT MAX(chapter) as m FROM verses WHERE book_number = ?', [id]);
                          maxChap = res.first['m'] as int;
                          setST(() => currentStep = 1);
                        })
                      : (currentStep == 1 
                          ? _buildNumberGrid(maxChap, (val) async {
                              tChap = val;
                              var res = await _db!.rawQuery('SELECT MAX(verse) as m FROM verses WHERE book_number = ? AND chapter = ?', [tId, val]);
                              maxVerse = res.first['m'] as int;
                              setST(() => currentStep = 2);
                            })
                          : _buildNumberGrid(maxVerse, (val) {
                              setState(() { _bookId = tId!; _chapter = tChap!; });
                              _loadContent(scrollToVerse: val);
                              Navigator.pop(context);
                            })
                        ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                      onPressed: () => Navigator.pop(context), 
                      child: const Text("BATAL", style: TextStyle(color: Colors.red))),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, a1, a2, child) => SlideTransition(position: Tween(begin: const Offset(0, -1), end: const Offset(0, 0)).animate(a1), child: child),
    );
  }

  Widget _buildBookSelector(StateSetter setST, Function(int, String) onSelect) {
    // FIX PL/PB Split menggunakan urutan index agar semua kitab muncul lengkap
    List<Map<String, dynamic>> pl = _allBooks.sublist(0, 39);
    List<Map<String, dynamic>> pb = _allBooks.sublist(39, 66);

    return ListView(
      children: [
        _sectionLabel("PERJANJIAN LAMA", Colors.pink[300]!),
        _gridBooks(pl, Colors.pink[300]!, onSelect),
        const SizedBox(height: 30),
        _sectionLabel("PERJANJIAN BARU", Colors.blue[300]!),
        _gridBooks(pb, Colors.blue[300]!, onSelect),
      ],
    );
  }

  Widget _sectionLabel(String t, Color c) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.1)));

  Widget _gridBooks(List<Map<String, dynamic>> list, Color col, Function(int, String) onSelect) {
    // Tombol berbentuk kotak konsisten dengan Pasal/Ayat
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: list.map((b) {
        String shortName = _getShortAbbr(b['long_name']);
        return InkWell(
          onTap: () => onSelect(b['book_number'], b['long_name']),
          child: Container(
            width: (MediaQuery.of(context).size.width - 70) / 5,
            height: 40,
            decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
            alignment: Alignment.center,
            child: Text(shortName, style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 10)),
          ),
        );
      }).toList(),
    );
  }

  // Grid seragam 5 kolom untuk Nomor Pasal & Ayat
  Widget _buildNumberGrid(int count, Function(int) onSelect) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 10, crossAxisSpacing: 10),
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
  void _executeAction(String type) {
    String output = "$_displayName $_chapter:${_selectedVerses.join(",")}\n\n";
    _selectedVerses.sort();
    for (var i in _selectedVerses) {
      final v = _verses.firstWhere((element) => element['verse'] == i);
      output += "$i. ${_cleanText(v['text'])}\n";
    }
    
    if (type == "SALIN") {
      Clipboard.setData(ClipboardData(text: output));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ayat disalin")));
    } else {
      Share.share(output);
    }
    setState(() => _selectedVerses.clear());
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
          // SWITCH VERSI TB / TJL
          TextButton(
            onPressed: () {
              setState(() => _currentVersion = (_currentVersion == "TB" ? "TJL" : "TB"));
              _initDatabase();
            },
            child: Text(_currentVersion, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: GestureDetector(
        // Pinch to Zoom
        onScaleUpdate: (details) {
          setState(() {
            _textSize = (18.0 * details.scale).clamp(12.0, 45.0);
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

                return InkWell(
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
                        style: TextStyle(fontSize: _textSize, color: Colors.black87, height: 1.6),
                        children: [
                          TextSpan(text: "$verseNum. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 14)),
                          TextSpan(text: _cleanText(v['text'])),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            // Floating Action Mode (Persis video demo bos)
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
                    IconButton(icon: const Icon(Icons.copy, color: Colors.white), onPressed: () => _executeAction("SALIN")),
                    IconButton(icon: const Icon(Icons.share, color: Colors.white), onPressed: () => _executeAction("BAGIKAN")),
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