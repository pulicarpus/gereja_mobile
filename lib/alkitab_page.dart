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
  
  // Variabel untuk menyimpan nama tampilan agar tidak panjang
  String _displayTitle = "Kejadian"; 

  final ScrollController _scrollController = ScrollController();
  late SharedPreferences _prefs;

  // --- DATA BAKU ALA SABDA/YUKU (66 KITAB) ---
  // Ini kunci agar nama tidak lagi "Surat Rasul Paulus..." tapi "Ibrani" atau "IBR"
  final List<Map<String, String>> _bibleMeta = [
    {"abbr": "KEJ", "full": "Kejadian"}, {"abbr": "KEL", "full": "Keluaran"}, {"abbr": "IMA", "full": "Imamat"}, {"abbr": "BIL", "full": "Bilangan"}, {"abbr": "ULA", "full": "Ulangan"},
    {"abbr": "YOS", "full": "Yosua"}, {"abbr": "HAK", "full": "Hakim-hakim"}, {"abbr": "RUT", "full": "Rut"}, {"abbr": "1SAM", "full": "1 Samuel"}, {"abbr": "2SAM", "full": "2 Samuel"},
    {"abbr": "1RAJ", "full": "1 Raja-raja"}, {"abbr": "2RAJ", "full": "2 Raja-raja"}, {"abbr": "1TAW", "full": "1 Tawarikh"}, {"abbr": "2TAW", "full": "2 Tawarikh"},
    {"abbr": "EZR", "full": "Ezra"}, {"abbr": "NEH", "full": "Nehemia"}, {"abbr": "EST", "full": "Ester"}, {"abbr": "AYU", "full": "Ayub"}, {"abbr": "MAZ", "full": "Mazmur"},
    {"abbr": "AMS", "full": "Amsal"}, {"abbr": "PKH", "full": "Pengkhotbah"}, {"abbr": "KID", "full": "Kidung Agung"}, {"abbr": "YES", "full": "Yesaya"},
    {"abbr": "YER", "full": "Yeremia"}, {"abbr": "RAT", "full": "Ratapan"}, {"abbr": "YEH", "full": "Yehezkiel"}, {"abbr": "DAN", "full": "Daniel"}, {"abbr": "HOS", "full": "Hosea"},
    {"abbr": "YOE", "full": "Yoel"}, {"abbr": "AMO", "full": "Amos"}, {"abbr": "OBA", "full": "Obaja"}, {"abbr": "YUN", "full": "Yunus"}, {"abbr": "MIK", "full": "Mikha"},
    {"abbr": "NAH", "full": "Nahum"}, {"abbr": "HAB", "full": "Habakuk"}, {"abbr": "ZEF", "full": "Zefanya"}, {"abbr": "HAG", "full": "Hagai"}, {"abbr": "ZAK", "full": "Zakharia"}, {"abbr": "MAL", "full": "Maleakhi"},
    {"abbr": "MAT", "full": "Matius"}, {"abbr": "MAR", "full": "Markus"}, {"abbr": "LUK", "full": "Lukas"}, {"abbr": "YOH", "full": "Yohanes"}, {"abbr": "KIS", "full": "Kisah Para Rasul"},
    {"abbr": "ROM", "full": "Roma"}, {"abbr": "1KOR", "full": "1 Korintus"}, {"abbr": "2KOR", "full": "2 Korintus"}, {"abbr": "GAL", "full": "Galatia"}, {"abbr": "EFE", "full": "Efesus"},
    {"abbr": "FIL", "full": "Filipi"}, {"abbr": "KOL", "full": "Kolose"}, {"abbr": "1TES", "full": "1 Tesalonika"}, {"abbr": "2TES", "full": "2 Tesalonika"}, {"abbr": "1TIM", "full": "1 Timotius"},
    {"abbr": "2TIM", "full": "2 Timotius"}, {"abbr": "TIT", "full": "Titus"}, {"abbr": "FLM", "full": "Filemon"}, {"abbr": "IBR", "full": "Ibrani"}, {"abbr": "YAK", "full": "Yakobus"},
    {"abbr": "1PET", "full": "1 Petrus"}, {"abbr": "2PET", "full": "2 Petrus"}, {"abbr": "1YOH", "full": "1 Yohanes"}, {"abbr": "2YOH", "full": "2 Yohanes"}, {"abbr": "3YOH", "full": "3 Yohanes"}, {"abbr": "YUD", "full": "Yudas"}, {"abbr": "WAH", "full": "Wahyu"}
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

  // Membersihkan tag HTML/SQLite
  String _cleanText(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>|\\f.*?\\f|\\.*?\\'), '').trim();
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
      } catch (e) { debugPrint("Error: $e"); }
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

    // Cari index berdasarkan book_number untuk mapping nama
    int idx = _allBooks.indexWhere((b) => b['book_number'] == _bookId);
    
    setState(() {
      _verses = verses;
      // Gunakan nama Full (Sabda Style) untuk App Bar
      _displayTitle = (idx >= 0 && idx < _bibleMeta.length) 
          ? _bibleMeta[idx]['full']! 
          : "Alkitab";
      _isLoading = false;
      _selectedVerses.clear();
    });

    if (scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.jumpTo((scrollToVerse - 1) * 85.0);
      });
    }
  }

  // --- DIALOG PEMILIH (GAYA SABDA) ---
  void _showSelectionDialog() {
    int step = 0; 
    int? tId; String tAbbr = ""; int? tChap; int mChap = 0; int mVer = 0;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Close",
      pageBuilder: (context, a1, a2) => StatefulBuilder(
        builder: (context, setST) => Material(
          color: Colors.black54,
          child: Column(
            children: [
              Container(
                height: MediaQuery.of(context).size.height * 0.85,
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white, 
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(25))
                ),
                padding: const EdgeInsets.fromLTRB(15, 50, 15, 15),
                child: Column(
                  children: [
                    Text(step == 0 ? "PILIH KITAB" : (step == 1 ? "$tAbbr - PASAL" : "$tAbbr $tChap - AYAT"),
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo[900], fontSize: 13, letterSpacing: 1.2)),
                    const Divider(height: 30),
                    Expanded(
                      child: step == 0 
                        ? _buildBookSelector(setST, (id, abbr) async {
                            tId = id; tAbbr = abbr;
                            var res = await _db!.rawQuery('SELECT MAX(chapter) as m FROM verses WHERE book_number = ?', [id]);
                            mChap = res.first['m'] as int;
                            setST(() => step = 1);
                          })
                        : (step == 1 
                            ? _buildNumberGrid(mChap, (val) async {
                                tChap = val;
                                var res = await _db!.rawQuery('SELECT MAX(verse) as m FROM verses WHERE book_number = ? AND chapter = ?', [tId, val]);
                                mVer = res.first['m'] as int;
                                setST(() => step = 2);
                              })
                            : _buildNumberGrid(mVer, (val) {
                                setState(() { _bookId = tId!; _chapter = tChap!; });
                                _loadContent(scrollToVerse: val);
                                Navigator.pop(context);
                              })
                          ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context), 
                        child: const Text("BATAL", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      transitionBuilder: (context, a1, a2, child) => SlideTransition(
        position: Tween(begin: const Offset(0, -1), end: const Offset(0, 0)).animate(a1), 
        child: child
      ),
    );
  }

  Widget _buildBookSelector(StateSetter setST, Function(int, String) onSelect) {
    return ListView(
      children: [
        _sectionLabel("PERJANJIAN LAMA", Colors.pink[400]!),
        _gridBooks(0, 39, Colors.pink[400]!, onSelect),
        const SizedBox(height: 25),
        _sectionLabel("PERJANJIAN BARU", Colors.blue[400]!),
        _gridBooks(39, 66, Colors.blue[400]!, onSelect),
      ],
    );
  }

  Widget _sectionLabel(String t, Color c) => Padding(
    padding: const EdgeInsets.only(bottom: 10), 
    child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 10))
  );

  Widget _gridBooks(int start, int end, Color col, Function(int, String) onSelect) {
    return Wrap(
      spacing: 7, runSpacing: 7,
      children: List.generate(end - start, (index) {
        int actualIdx = start + index;
        var book = _allBooks[actualIdx];
        // AMBIL SINGKATAN DARI bibleMeta (SABDA STYLE)
        String shortName = _bibleMeta[actualIdx]['abbr']!; 
        return InkWell(
          onTap: () => onSelect(book['book_number'], shortName),
          child: Container(
            width: (MediaQuery.of(context).size.width - 65) / 5,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.grey[50], 
              borderRadius: BorderRadius.circular(6), 
              border: Border.all(color: Colors.grey[200]!)
            ),
            alignment: Alignment.center,
            child: Text(shortName, style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 9)),
          ),
        );
      }),
    );
  }

  Widget _buildNumberGrid(int count, Function(int) onSelect) {
    return GridView.builder(
      padding: const EdgeInsets.only(top: 10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.3
      ),
      itemCount: count,
      itemBuilder: (context, i) => InkWell(
        onTap: () => onSelect(i + 1),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey[50], 
            borderRadius: BorderRadius.circular(6), 
            border: Border.all(color: Colors.grey[200]!)
          ),
          alignment: Alignment.center, 
          child: Text("${i + 1}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
        title: GestureDetector(
          onTap: _showSelectionDialog,
          child: Row(
            children: [
              // Judul di App Bar sekarang pakai nama standar (misal: "Ibrani")
              Text("$_displayTitle $_chapter", style: const TextStyle(fontSize: 18)),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              setState(() => _currentVersion = (_currentVersion == "TB" ? "TJL" : "TB"));
              _initDatabase();
            },
            icon: Text(_currentVersion, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : GestureDetector(
        onScaleUpdate: (d) => setState(() {
          _textSize = (18.0 * d.scale).clamp(12.0, 45.0);
          _prefs.setDouble('text_size', _textSize);
        }),
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
                          TextSpan(text: _cleanText(v['text'])),
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
                color: Colors.indigo[900], padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => _selectedVerses.clear())),
                    Text("${_selectedVerses.length} dipilih", style: const TextStyle(color: Colors.white)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.copy, color: Colors.white), onPressed: () {
                      _selectedVerses.sort();
                      String t = "$_displayTitle $_chapter:${_selectedVerses.join(",")}\n";
                      for(var n in _selectedVerses) t += "$n. ${_cleanText(_verses.firstWhere((e)=>e['verse']==n)['text'])}\n";
                      Clipboard.setData(ClipboardData(text: t));
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