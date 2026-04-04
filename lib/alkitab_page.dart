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
  Map<String, String> _savedNotes = {}; // Untuk simpan cache catatan agar muncul ikon
  
  bool _isLoading = true;
  bool _isSearching = false;
  double _textSize = 18.0;
  String _currentVersion = "TB"; 
  int _bookId = 10; 
  int _chapter = 1;
  String _displayTitle = "Kejadian"; 

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
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
    _refreshNotesCache();
    await _initDatabase();
  }

  // Load semua catatan ke memori agar bisa kasih tanda di ayat
  void _refreshNotesCache() {
    Map<String, String> tempNotes = {};
    List<String> keys = _prefs.getStringList("ALL_NOTE_KEYS") ?? [];
    for (String k in keys) {
      String? data = _prefs.getString(k);
      if (data != null) {
        String nas = data.split("~|~")[0]; // Ambil bagian Nas (mis: Kejadian 1:1)
        tempNotes[nas] = data;
      }
    }
    setState(() => _savedNotes = tempNotes);
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
        _scrollController.animateTo((scrollToVerse - 1) * 85.0, duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
      });
    }
  }

  void _bukaHalamanCatatan() {
    _selectedVerses.sort();
    String nas = "$_displayTitle $_chapter:${_selectedVerses.join(",")}";
    String isiAyat = "";
    for (var vNum in _selectedVerses) {
      final v = _verses.firstWhere((e) => e['verse'] == vNum);
      isiAyat += "$vNum. ${_cleanText(v['text'])}\n";
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NoteEditorPage(
          nas: nas,
          isiAyat: isiAyat,
          onSave: (title, content) async {
            String key = "Note_${DateTime.now().millisecondsSinceEpoch}";
            String dataFinal = "$nas~|~$title~|~Pengkhotbah~|~${DateTime.now().toString()}~|~Pendahuluan~|~$content";
            
            List<String> allKeys = _prefs.getStringList("ALL_NOTE_KEYS") ?? [];
            allKeys.add(key);
            await _prefs.setStringList("ALL_NOTE_KEYS", allKeys);
            await _prefs.setString(key, dataFinal);

            _refreshNotesCache(); // Update tampilan agar ikon muncul
            setState(() => _selectedVerses.clear());
          },
        ),
      ),
    );
  }

  void _bukaDaftarCatatan() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => NoteListPage(prefs: _prefs, onNoteSelected: (nasFull) {
        // Logika loncat ke ayat dari catatan
        // Format nasFull biasanya: "Kejadian 1:1"
        try {
          List<String> parts = nasFull.split(" ");
          String kitabName = parts[0];
          List<String> chapVer = parts[1].split(":");
          int chap = int.parse(chapVer[0]);
          int ver = int.parse(chapVer[1].split(",")[0]);

          int bIdx = _bibleMeta.indexWhere((m) => m['full'] == kitabName);
          if (bIdx != -1) {
            setState(() { 
              _bookId = _allBooks[bIdx]['book_number']; 
              _chapter = chap; 
            });
            _loadContent(scrollToVerse: ver);
          }
        } catch(e) {}
      })),
    ).then((_) => _refreshNotesCache());
  }

  PreferredSizeWidget _buildAppBar() {
    if (_isSearching) {
      return AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black87), onPressed: () => setState(() { _isSearching = false; _searchCtrl.clear(); })),
        title: TextField(
          controller: _searchCtrl, autofocus: true,
          decoration: const InputDecoration(hintText: "Cari kata...", border: InputBorder.none),
          onSubmitted: (val) => _prosesCari(val),
        ),
        actions: [IconButton(icon: const Icon(Icons.search, color: Colors.indigo), onPressed: () => _prosesCari(_searchCtrl.text))],
      );
    }
    return AppBar(
      backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
      title: GestureDetector(onTap: _showSelectionDialog, child: Row(children: [Text("$_displayTitle $_chapter", style: const TextStyle(fontSize: 18)), const Icon(Icons.arrow_drop_down)])),
      actions: [
        IconButton(icon: const Icon(Icons.search), onPressed: () => setState(() => _isSearching = true)),
        IconButton(icon: const Icon(Icons.book), onPressed: _bukaDaftarCatatan), 
        TextButton(
          onPressed: () { setState(() => _currentVersion = (_currentVersion == "TB" ? "TJL" : "TB")); _initDatabase(); },
          child: Text(_currentVersion, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  void _prosesCari(String query) async {
    if(query.trim().length < 3) return;
    var results = await _db!.query('verses', where: "text LIKE ?", whereArgs: ["%$query%"], limit: 100);
    _showSearchResults(results, query);
  }

  void _showSearchResults(List<Map<String, dynamic>> results, String query) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Hasil: '$query'"),
        content: SizedBox(width: double.maxFinite, child: ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, i) {
            var r = results[i];
            int bNum = r['book_number'];
            int idx = _allBooks.indexWhere((b) => b['book_number'] == bNum);
            return ListTile(
              title: Text("${_bibleMeta[idx]['abbr']} ${r['chapter']}:${r['verse']}", style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(_cleanText(r['text'])),
              onTap: () { setState(() { _bookId = bNum; _chapter = r['chapter']; _isSearching = false; }); _loadContent(scrollToVerse: r['verse']); Navigator.pop(context); },
            );
          },
        )),
      ),
    );
  }

  // --- PEMILIH KITAB ---
  void _showSelectionDialog() {
    int step = 0; int? tId; String tAbbr = ""; int? tChap; int mChap = 0; int mVer = 0;
    showGeneralDialog(
      context: context, barrierDismissible: true, barrierLabel: "Tutup",
      pageBuilder: (context, a1, a2) => StatefulBuilder(
        builder: (context, setST) => Material(
          color: Colors.black54,
          child: Center(
            child: Container(
              height: MediaQuery.of(context).size.height * 0.8, width: MediaQuery.of(context).size.width * 0.9,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.all(15),
              child: Column(children: [
                Text(step == 0 ? "PILIH KITAB" : (step == 1 ? "$tAbbr - PASAL" : "$tAbbr $tChap - AYAT"), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Divider(),
                Expanded(child: step == 0 ? _buildBookSelector(setST, (id, abbr) async {
                  tId = id; tAbbr = abbr;
                  var res = await _db!.rawQuery('SELECT MAX(chapter) as m FROM verses WHERE book_number = ?', [id]);
                  mChap = res.first['m'] as int; setST(() => step = 1);
                }) : (step == 1 ? _buildNumberGrid(mChap, (val) async {
                  tChap = val;
                  var res = await _db!.rawQuery('SELECT MAX(verse) as m FROM verses WHERE book_number = ? AND chapter = ?', [tId, val]);
                  mVer = res.first['m'] as int; setST(() => step = 2);
                }) : _buildNumberGrid(mVer, (val) {
                  setState(() { _bookId = tId!; _chapter = tChap!; }); _loadContent(scrollToVerse: val); Navigator.pop(context);
                }))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookSelector(StateSetter setST, Function(int, String) onSelect) {
    return ListView(children: [
      _gridBooks(0, 39, Colors.pink, onSelect),
      const Divider(),
      _gridBooks(39, 66, Colors.blue, onSelect),
    ]);
  }

  Widget _gridBooks(int s, int e, Color c, Function(int, String) onSelect) {
    return Wrap(spacing: 5, runSpacing: 5, children: List.generate(e - s, (i) {
      int idx = s + i;
      return InkWell(
        onTap: () => onSelect(_allBooks[idx]['book_number'], _bibleMeta[idx]['abbr']!),
        child: Container(width: 55, height: 40, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(5)), alignment: Alignment.center, child: Text(_bibleMeta[idx]['abbr']!, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 11))),
      );
    }));
  }

  Widget _buildNumberGrid(int count, Function(int) onSelect) {
    return GridView.builder(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5), itemCount: count, itemBuilder: (context, i) => IconButton(onPressed: () => onSelect(i+1), icon: Text("${i+1}", style: const TextStyle(fontWeight: FontWeight.bold))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : GestureDetector(
        onScaleUpdate: (d) => setState(() { _textSize = (18.0 * d.scale).clamp(12.0, 45.0); _prefs.setDouble('text_size', _textSize); }),
        child: Stack(
          children: [
            ListView.builder(
              controller: _scrollController, padding: const EdgeInsets.all(20), itemCount: _verses.length,
              itemBuilder: (context, i) {
                final v = _verses[i];
                final bool isSelected = _selectedVerses.contains(v['verse']);
                // Cek apakah ayat ini ada catatannya
                String currentNasKey = "$_displayTitle $_chapter:${v['verse']}";
                bool hasNote = _savedNotes.containsKey(currentNasKey);

                return InkWell(
                  onTap: () => setState(() { isSelected ? _selectedVerses.remove(v['verse']) : _selectedVerses.add(v['verse']); }),
                  child: Container(
                    color: isSelected ? Colors.indigo[50] : Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: RichText(text: TextSpan(style: TextStyle(fontSize: _textSize, color: Colors.black87, height: 1.6), children: [
                          TextSpan(text: "${v['verse']}. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                          TextSpan(text: _cleanText(v['text'])),
                        ]))),
                        if (hasNote) const Icon(Icons.edit_note, color: Colors.orange, size: 20), // TANDA CATATAN DI UJUNG
                      ],
                    ),
                  ),
                );
              },
            ),
            if (_selectedVerses.isNotEmpty) Positioned(top: 0, left: 0, right: 0, child: Container(color: Colors.indigo[900], child: Row(children: [
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => _selectedVerses.clear())),
              Text("${_selectedVerses.length}", style: const TextStyle(color: Colors.white)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.copy, color: Colors.white), onPressed: () {
                _selectedVerses.sort(); String t = "$_displayTitle $_chapter:${_selectedVerses.join(",")}\n";
                for(var n in _selectedVerses) t += "$n. ${_cleanText(_verses.firstWhere((e)=>e['verse']==n)['text'])}\n";
                Clipboard.setData(ClipboardData(text: t)); setState(() => _selectedVerses.clear());
              }),
              IconButton(icon: const Icon(Icons.share, color: Colors.white), onPressed: () {
                _selectedVerses.sort(); String t = "$_displayTitle $_chapter:${_selectedVerses.join(",")}\n";
                for(var n in _selectedVerses) t += "$n. ${_cleanText(_verses.firstWhere((e)=>e['verse']==n)['text'])}\n";
                Share.share(t); setState(() => _selectedVerses.clear());
              }),
              IconButton(icon: const Icon(Icons.note_add, color: Colors.white), onPressed: _bukaHalamanCatatan),
            ]))),
          ],
        ),
      ),
    );
  }
}

// --- HALAMAN EDITOR CATATAN ---
class NoteEditorPage extends StatefulWidget {
  final String nas; final String isiAyat; final Function(String, String) onSave;
  const NoteEditorPage({super.key, required this.nas, required this.isiAyat, required this.onSave});
  @override State<NoteEditorPage> createState() => _NoteEditorPageState();
}
class _NoteEditorPageState extends State<NoteEditorPage> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _contentCtrl = TextEditingController(text: "\n\n1. ");
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Tulis Catatan"), actions: [IconButton(icon: const Icon(Icons.check), onPressed: () { widget.onSave(_titleCtrl.text, _contentCtrl.text); Navigator.pop(context); })]),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.nas, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo)),
        Text(widget.isiAyat, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
        const Divider(),
        TextField(controller: _titleCtrl, decoration: const InputDecoration(hintText: "Judul Khotbah"), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        TextField(controller: _contentCtrl, maxLines: null, decoration: const InputDecoration(hintText: "Isi catatan...", border: InputBorder.none)),
      ])),
    );
  }
}

// --- HALAMAN DAFTAR CATATAN ---
class NoteListPage extends StatelessWidget {
  final SharedPreferences prefs;
  final Function(String) onNoteSelected;
  const NoteListPage({super.key, required this.prefs, required this.onNoteSelected});

  @override
  Widget build(BuildContext context) {
    List<String> keys = prefs.getStringList("ALL_NOTE_KEYS") ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text("Daftar Catatan")),
      body: keys.isEmpty ? const Center(child: Text("Belum ada catatan")) : ListView.builder(
        itemCount: keys.length,
        itemBuilder: (context, i) {
          String? raw = prefs.getString(keys[i]);
          if (raw == null) return const SizedBox();
          List<String> parts = raw.split("~|~"); // Nas, Judul, Pengkhotbah, Tgl, Pend, Isi
          return ListTile(
            leading: const Icon(Icons.note, color: Colors.indigo),
            title: Text(parts[1].isEmpty ? "Tanpa Judul" : parts[1]),
            subtitle: Text("${parts[0]}\n${parts[3]}"),
            isThreeLine: true,
            onTap: () {
              onNoteSelected(parts[0]);
              Navigator.pop(context);
            },
            trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async {
              keys.removeAt(i);
              await prefs.setStringList("ALL_NOTE_KEYS", keys);
              (context as Element).markNeedsBuild(); // Refresh sederhana
            }),
          );
        },
      ),
    );
  }
}