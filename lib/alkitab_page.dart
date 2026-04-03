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
  String _displayTitle = "Kejadian"; 

  final ScrollController _scrollController = ScrollController();
  late SharedPreferences _prefs;

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

    int idx = _allBooks.indexWhere((b) => b['book_number'] == _bookId);
    
    setState(() {
      _verses = verses;
      _displayTitle = (idx >= 0 && idx < _bibleMeta.length) ? _bibleMeta[idx]['full']! : "Alkitab";
      _isLoading = false;
      _selectedVerses.clear();
    });

    if (scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.jumpTo((scrollToVerse - 1) * 85.0);
      });
    }
  }

  // --- FITUR CATATAN (GAYA KOTLIN) ---
  void _tambahCatatan() async {
    _selectedVerses.sort();
    String nas = "$_displayTitle $_chapter:${_selectedVerses.join(",")}";
    String isiAyat = "";
    for (var vNum in _selectedVerses) {
      final v = _verses.firstWhere((e) => e['verse'] == vNum);
      isiAyat += "$vNum. ${_cleanText(v['text'])}\n";
    }

    TextEditingController titleCtrl = TextEditingController();
    TextEditingController contentCtrl = TextEditingController(text: "1. ");

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Catatan: $nas", style: const TextStyle(fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(hintText: "Judul Khotbah/Catatan")),
            const SizedBox(height: 10),
            TextField(controller: contentCtrl, maxLines: 5, decoration: const InputDecoration(hintText: "Isi Catatan...")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("BATAL")),
          ElevatedButton(
            onPressed: () {
              String key = "Note_${DateTime.now().millisecondsSinceEpoch}";
              String dataFinal = "$nas~|~${titleCtrl.text}~|~Pengkhotbah~|~${DateTime.now().toString()}~|~Pendahuluan~|~${contentCtrl.text}";
              
              List<String> allKeys = _prefs.getStringSet("ALL_NOTE_KEYS")?.toList() ?? [];
              allKeys.add(key);
              _prefs.setStringSet("ALL_NOTE_KEYS", allKeys.toSet());
              _prefs.setString(key, dataFinal);

              Navigator.pop(context);
              setState(() => _selectedVerses.clear());
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Catatan tersimpan")));
            },
            child: const Text("SIMPAN"),
          )
        ],
      ),
    );
  }

  // --- FITUR PENCARIAN ---
  void _showSearchDialog() {
    TextEditingController searchCtrl = TextEditingController();
    String scope = "SEMUA"; // SEMUA, PL, PB, KITAB

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setST) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: "Cari kata...",
                  suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () async {
                    String query = searchCtrl.text.trim();
                    if(query.length < 3) return;
                    
                    String whereClause = "text LIKE ?";
                    List<dynamic> args = ["%$query%"];

                    if(scope == "PL") { whereClause += " AND book_number <= 390"; }
                    else if(scope == "PB") { whereClause += " AND book_number > 390"; }
                    else if(scope == "KITAB") { whereClause += " AND book_number = $_bookId"; }

                    var results = await _db!.query('verses', where: whereClause, whereArgs: args, limit: 100);
                    
                    if(!mounted) return;
                    Navigator.pop(context);
                    _showSearchResults(results, query);
                  }),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ["SEMUA", "PL", "PB", "KITAB"].map((s) => ChoiceChip(
                  label: Text(s, style: const TextStyle(fontSize: 10)),
                  selected: scope == s,
                  onSelected: (val) => setST(() => scope = s),
                )).toList(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showSearchResults(List<Map<String, dynamic>> results, String query) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Hasil: ${results.length} ditemukan", style: const TextStyle(fontSize: 14)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, i) {
              var r = results[i];
              int bNum = r['book_number'];
              int idx = _allBooks.indexWhere((b) => b['book_number'] == bNum);
              String bName = _bibleMeta[idx]['abbr']!;
              return ListTile(
                title: Text("$bName ${r['chapter']}:${r['verse']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                subtitle: Text(_cleanText(r['text']), maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () {
                  setState(() { _bookId = bNum; _chapter = r['chapter']; });
                  _loadContent(scrollToVerse: r['verse']);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // --- DIALOG PEMILIH KITAB (FONT DIPERBESAR) ---
  void _showSelectionDialog() {
    int step = 0; int? tId; String tAbbr = ""; int? tChap; int mChap = 0; int mVer = 0;
    showGeneralDialog(
      context: context, barrierDismissible: true, barrierLabel: "Tutup",
      pageBuilder: (context, a1, a2) => StatefulBuilder(
        builder: (context, setST) => Material(
          color: Colors.black54,
          child: Column(children: [
            Container(
              height: MediaQuery.of(context).size.height * 0.85, width: double.infinity,
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(bottom: Radius.circular(25))),
              padding: const EdgeInsets.fromLTRB(15, 50, 15, 15),
              child: Column(children: [
                Text(step == 0 ? "PILIH KITAB" : (step == 1 ? "$tAbbr - PASAL" : "$tAbbr $tChap - AYAT"),
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo[900], fontSize: 14, letterSpacing: 1.2)),
                const Divider(height: 30),
                Expanded(
                  child: step == 0 ? _buildBookSelector(setST, (id, abbr) async {
                        tId = id; tAbbr = abbr;
                        var res = await _db!.rawQuery('SELECT MAX(chapter) as m FROM verses WHERE book_number = ?', [id]);
                        mChap = res.first['m'] as int; setST(() => step = 1);
                      }) : (step == 1 ? _buildNumberGrid(mChap, (val) async {
                            tChap = val;
                            var res = await _db!.rawQuery('SELECT MAX(verse) as m FROM verses WHERE book_number = ? AND chapter = ?', [tId, val]);
                            mVer = res.first['m'] as int; setST(() => step = 2);
                          }) : _buildNumberGrid(mVer, (val) {
                            setState(() { _bookId = tId!; _chapter = tChap!; });
                            _loadContent(scrollToVerse: val); Navigator.pop(context);
                          })),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("BATAL", style: TextStyle(color: Colors.red))),
              ]),
            ),
          ]),
        ),
      ),
      transitionBuilder: (context, a1, a2, child) => SlideTransition(position: Tween(begin: const Offset(0, -1), end: const Offset(0, 0)).animate(a1), child: child),
    );
  }

  Widget _buildBookSelector(StateSetter setST, Function(int, String) onSelect) {
    return ListView(children: [
      _sectionLabel("PERJANJIAN LAMA", Colors.pink[400]!),
      _gridBooks(0, 39, Colors.pink[400]!, onSelect),
      const SizedBox(height: 25),
      _sectionLabel("PERJANJIAN BARU", Colors.blue[400]!),
      _gridBooks(39, 66, Colors.blue[400]!, onSelect),
    ]);
  }

  Widget _sectionLabel(String t, Color c) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 11)));

  Widget _gridBooks(int start, int end, Color col, Function(int, String) onSelect) {
    return Wrap(spacing: 7, runSpacing: 7, children: List.generate(end - start, (index) {
        int actualIdx = start + index;
        var book = _allBooks[actualIdx];
        String shortName = _bibleMeta[actualIdx]['abbr']!; 
        return InkWell(
          onTap: () => onSelect(book['book_number'], shortName),
          child: Container(
            width: (MediaQuery.of(context).size.width - 65) / 5, height: 42, // Dipertinggi sedikit
            decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
            alignment: Alignment.center,
            child: Text(shortName, style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 11)), // FONT DIPERBESAR & BOLD
          ),
        );
      }),
    );
  }

  Widget _buildNumberGrid(int count, Function(int) onSelect) {
    return GridView.builder(
      padding: const EdgeInsets.only(top: 10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.2),
      itemCount: count,
      itemBuilder: (context, i) => InkWell(
        onTap: () => onSelect(i + 1),
        child: Container(
          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
          alignment: Alignment.center, child: Text("${i + 1}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), // FONT DIPERBESAR
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
        title: GestureDetector(
          onTap: _showSelectionDialog,
          child: Row(children: [Text("$_displayTitle $_chapter", style: const TextStyle(fontSize: 18)), const Icon(Icons.arrow_drop_down)]),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _showSearchDialog), // TOMBOL CARI
          IconButton(icon: const Icon(Icons.book), onPressed: () { /* Navigasi ke Daftar Catatan */ }), // TOMBOL CATATAN
          TextButton(
            onPressed: () { setState(() => _currentVersion = (_currentVersion == "TB" ? "TJL" : "TB")); _initDatabase(); },
            child: Text(_currentVersion, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : GestureDetector(
        onScaleUpdate: (d) => setState(() { _textSize = (18.0 * d.scale).clamp(12.0, 45.0); _prefs.setDouble('text_size', _textSize); }),
        child: Stack(
          children: [
            ListView.builder(
              controller: _scrollController, padding: const EdgeInsets.all(20),
              itemCount: _verses.length,
              itemBuilder: (context, i) {
                final v = _verses[i];
                final bool isSelected = _selectedVerses.contains(v['verse']);
                return InkWell(
                  onTap: () => setState(() { isSelected ? _selectedVerses.remove(v['verse']) : _selectedVerses.add(v['verse']); }),
                  child: Container(
                    color: isSelected ? Colors.indigo[50] : Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 8),
                    child: RichText(text: TextSpan(
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
            // FLOATING MENU SAAT AYAT DIPILIH
            if (_selectedVerses.isNotEmpty) Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                color: Colors.indigo[900], padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => _selectedVerses.clear())),
                    Text("${_selectedVerses.length}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(tooltip: "Salin", icon: const Icon(Icons.copy, color: Colors.white, size: 20), onPressed: () {
                      _selectedVerses.sort(); String t = "$_displayTitle $_chapter:${_selectedVerses.join(",")}\n";
                      for(var n in _selectedVerses) t += "$n. ${_cleanText(_verses.firstWhere((e)=>e['verse']==n)['text'])}\n";
                      Clipboard.setData(ClipboardData(text: t)); setState(() => _selectedVerses.clear());
                    }),
                    IconButton(tooltip: "Bagikan", icon: const Icon(Icons.share, color: Colors.white, size: 20), onPressed: () {
                      _selectedVerses.sort(); String t = "$_displayTitle $_chapter:${_selectedVerses.join(",")}\n";
                      for(var n in _selectedVerses) t += "$n. ${_cleanText(_verses.firstWhere((e)=>e['verse']==n)['text'])}\n";
                      Share.share(t); setState(() => _selectedVerses.clear());
                    }),
                    IconButton(tooltip: "Catatan", icon: const Icon(Icons.note_add, color: Colors.white, size: 20), onPressed: _tambahCatatan),
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