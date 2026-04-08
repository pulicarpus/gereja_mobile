import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart'; 
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// Pastikan file-file ini tersedia di project Anda
import 'bible_models.dart';
import 'notes_pages.dart';
import 'search_page.dart';

class AlkitabPage extends StatefulWidget {
  const AlkitabPage({super.key});
  @override
  State<AlkitabPage> createState() => _AlkitabPageState();
}

class _AlkitabPageState extends State<AlkitabPage> {
  Database? _db;
  List<Map<String, dynamic>> _verses = [];
  Map<int, List<String>> _perikopMap = {}; 
  List<BibleBook> _allBooks = [];
  Set<int> _selectedVerses = {};
  Map<int, List<String>> _verseNotesMap = {}; 
  final ScrollController _scrollController = ScrollController();
  
  String _currentVersion = "TB.SQLite3"; 
  int _currentBookNum = 10; 
  int _currentChapter = 1;
  bool _isLoading = true;
  late SharedPreferences _prefs;

  double _fontSize = 18.0;
  double _baseFontSize = 18.0;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  String _cleanText(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  Future<void> _initApp() async {
    _prefs = await SharedPreferences.getInstance();
    _currentBookNum = _prefs.getInt('LAST_BOOK_NUM') ?? 10; 
    _currentChapter = _prefs.getInt('LAST_CHAPTER') ?? 1;
    _currentVersion = _prefs.getString('LAST_VERSION') ?? "TB.SQLite3"; 
    _fontSize = _prefs.getDouble('LAST_FONT_SIZE') ?? 18.0;
    await _loadDatabase();
  }

  void _saveLastPosition() {
    _prefs.setInt('LAST_BOOK_NUM', _currentBookNum);
    _prefs.setInt('LAST_CHAPTER', _currentChapter);
    _prefs.setString('LAST_VERSION', _currentVersion);
  }

  void _saveFontSize() {
    _prefs.setDouble('LAST_FONT_SIZE', _fontSize);
  }

  Future<void> _changeVersion(String newVersion) async {
    if (_currentVersion == newVersion) return;
    setState(() { _currentVersion = newVersion; _isLoading = true; });
    _saveLastPosition(); 
    if (_db != null) { await _db!.close(); _db = null; }
    await _loadDatabase();
  }

  Future<void> _loadDatabase() async {
    setState(() => _isLoading = true);
    try {
      var dbPath = await getDatabasesPath();
      String path = p.join(dbPath, _currentVersion);
      bool exists = await databaseExists(path);
      if (!exists) {
        ByteData data = await rootBundle.load("assets/$_currentVersion");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      }
      _db = await openDatabase(path);
      final bookData = await _db!.query('books', orderBy: 'book_number ASC');
      setState(() {
        _allBooks = bookData.map((e) => BibleBook(
          bookNumber: e['book_number'] as int, 
          name: e['long_name'].toString(),
          shortName: e['short_name'].toString()
        )).toList();
      });
      await _loadContent();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadContent({int? scrollToVerse}) async {
    if (_db == null) return;
    try {
      final verseData = await _db!.query('verses', 
          where: 'book_number = ? AND chapter = ?', 
          whereArgs: [_currentBookNum, _currentChapter],
          orderBy: 'verse ASC');
      List<Map<String, dynamic>> storyData = [];
      try {
        storyData = await _db!.query('stories',
            where: 'book_number = ? AND chapter = ?',
            whereArgs: [_currentBookNum, _currentChapter],
            orderBy: 'verse ASC, order_if_several ASC');
      } catch (e) {}
      _perikopMap.clear();
      for (var s in storyData) {
        int vNum = s['verse'] as int;
        String title = s['title'].toString();
        if (!_perikopMap.containsKey(vNum)) _perikopMap[vNum] = [];
        _perikopMap[vNum]!.add(title);
      }
      _verses = verseData;
      await _syncNotes(); 
      setState(() { _isLoading = false; _selectedVerses.clear(); });
      if (scrollToVerse != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            double estimatedHeight = (_fontSize * 4) + 20; 
            double position = (scrollToVerse - 1) * estimatedHeight; 
            _scrollController.animateTo(position, duration: const Duration(milliseconds: 600), curve: Curves.easeOut);
          }
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncNotes() async {
    _verseNotesMap.clear();
    final allKeys = _prefs.getStringList("ALL_NOTE_KEYS") ?? [];
    if (_allBooks.isEmpty) return;
    String currentBookName = _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    String prefix = "$currentBookName $_currentChapter:";
    for (var key in allKeys) {
      String? rawData = _prefs.getString(key);
      if (rawData != null && rawData.split("~|~")[0].startsWith(prefix)) {
        try {
          int lastVerse = int.parse(rawData.split("~|~")[0].split(":")[1].split(RegExp(r'[-,]')).last);
          if (!_verseNotesMap.containsKey(lastVerse)) _verseNotesMap[lastVerse] = [];
          _verseNotesMap[lastVerse]!.add(key);
        } catch (e) {}
      }
    }
  }

  void _showNoteSelection(List<String> keys) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.all(16.0), child: Text("Pilih Catatan", style: TextStyle(fontWeight: FontWeight.bold))),
          const Divider(),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: keys.length,
              itemBuilder: (context, i) {
                String key = keys[i];
                String raw = _prefs.getString(key) ?? "";
                return ListTile(
                  leading: const Text("📝"),
                  title: Text(raw.split("~|~")[0]),
                  onTap: () { Navigator.pop(context); _openNote(key); },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openNote(String key) {
    String? raw = _prefs.getString(key);
    if (raw != null) {
      Navigator.push(context, MaterialPageRoute(
        builder: (c) => NoteEditorPage(nas: raw.split("~|~")[0], prefs: _prefs, existingKey: key, db: _db!, allBooks: _allBooks)
      )).then((_) => _loadContent());
    }
  }

  void _showNavigation() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true, 
      barrierLabel: "Nav",
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => Align(
        alignment: Alignment.topCenter,
        child: Material(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(25)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
            child: _NavSheet(
              allBooks: _allBooks, db: _db!, currentVersion: _currentVersion,
              onVersionChange: (v) { Navigator.pop(context); _changeVersion(v); },
              onSelectionComplete: (b, c, v) {
                setState(() { _currentBookNum = b; _currentChapter = c; });
                _saveLastPosition(); _loadContent(scrollToVerse: v);
              },
            ),
          ),
        ),
      ),
      transitionBuilder: (context, anim1, anim2, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
  }

  void _showActionMenu() {
    if (_selectedVerses.isEmpty) return;
    List<int> sorted = _selectedVerses.toList()..sort();
    String bookName = _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    String nas = "$bookName $_currentChapter:${sorted.join(",")}";
    showModalBottomSheet(
      context: context, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), 
      builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.add_comment, color: Colors.blue), title: const Text("Buat Catatan"), onTap: () {
          Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: nas, prefs: _prefs, db: _db!, allBooks: _allBooks))).then((_) => _loadContent()); 
        }),
        ListTile(leading: const Icon(Icons.copy), title: const Text("Salin"), onTap: () {
          Clipboard.setData(ClipboardData(text: nas)); Navigator.pop(context); setState(() => _selectedVerses.clear());
        }),
      ])
    );
  }

  // 👇 FITUR KAMUS ALKITAB (SABDA) 👇
  void _tampilkanDialogKamus(BuildContext context) {
    final TextEditingController searchController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [Icon(Icons.menu_book, color: Colors.indigo), SizedBox(width: 10), Text("Kamus Alkitab")]),
        content: TextField(
          controller: searchController,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Cari arti kata..."),
          onSubmitted: (v) { Navigator.pop(context); _bukaKamusDiBrowser(v); },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(onPressed: () { Navigator.pop(context); _bukaKamusDiBrowser(searchController.text); }, child: const Text("Cari")),
        ],
      ),
    );
  }

  Future<void> _bukaKamusDiBrowser(String kata) async {
    if (kata.trim().isEmpty) return;
    final Uri url = Uri.parse("https://alkitab.sabda.org/dictionary.php?word=${kata.trim()}");
    try { await launchUrl(url, mode: LaunchMode.inAppBrowserView); } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal membuka kamus.")));
    }
  }

  // 👇 LOGIKA PERIKOP RUMIT (DENGAN REFERENSI SILANG WARNA BIRU) 👇
  Widget _buildPerikopItem(String title) {
    if (!title.contains("<x>")) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Center(child: Text(title, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: _fontSize + 1))));
    }
    List<InlineSpan> spans = [];
    final regex = RegExp(r'<x>(.*?)</x>');
    title.splitMapJoin(regex, onMatch: (Match m) {
      String rawRef = m.group(1) ?? ""; 
      final refData = RegExp(r'(\d+)\s+(\d+):(\d+)').firstMatch(rawRef);
      if (refData != null) {
        int bNum = int.parse(refData.group(1)!);
        int chap = int.parse(refData.group(2)!);
        int vStart = int.parse(refData.group(3)!);
        String bookShort = bNum.toString();
        try { bookShort = _allBooks.firstWhere((b) => b.bookNumber == bNum).shortName; } catch (e) {}
        spans.add(TextSpan(text: rawRef.replaceFirst(bNum.toString(), bookShort), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()..onTap = () { setState(() { _currentBookNum = bNum; _currentChapter = chap; }); _saveLastPosition(); _loadContent(scrollToVerse: vStart); },
        ));
      } else { spans.add(TextSpan(text: rawRef)); }
      return "";
    }, onNonMatch: (String text) { spans.add(TextSpan(text: text)); return ""; });
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Center(child: RichText(textAlign: TextAlign.center, text: TextSpan(style: TextStyle(fontSize: _fontSize - 2, color: Colors.black, fontStyle: FontStyle.italic), children: spans))));
  }

  @override
  Widget build(BuildContext context) {
    String bookName = _allBooks.isEmpty ? "" : _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
        title: InkWell(onTap: _showNavigation, child: Row(mainAxisSize: MainAxisSize.min, children: [Text("$bookName $_currentChapter"), const Icon(Icons.arrow_drop_down)])),
        actions: [
          IconButton(icon: const Icon(Icons.menu_book), onPressed: () => _tampilkanDialogKamus(context)),
          IconButton(icon: const Icon(Icons.event_note), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => NoteListPage(prefs: _prefs, db: _db!, allBooks: _allBooks))).then((_) => _loadContent())),
          IconButton(icon: const Icon(Icons.search), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => SearchPage(db: _db!, allBooks: _allBooks, currentBookNum: _currentBookNum))).then((res) { if (res != null) { setState(() { _currentBookNum = res['book_number']; _currentChapter = res['chapter']; }); _saveLastPosition(); _loadContent(scrollToVerse: res['verse']); } })),
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : GestureDetector(
        onScaleStart: (d) => _baseFontSize = _fontSize,
        onScaleUpdate: (d) => setState(() => _fontSize = (_baseFontSize * d.scale).clamp(12.0, 40.0)),
        onScaleEnd: (d) => _saveFontSize(),
        child: ListView.builder(
          controller: _scrollController,
          itemCount: _verses.length,
          itemBuilder: (context, i) {
            final v = _verses[i];
            final vNum = v['verse'] as int;
            final isSelected = _selectedVerses.contains(vNum);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_perikopMap.containsKey(vNum)) ..._perikopMap[vNum]!.map((t) => _buildPerikopItem(t)),
                GestureDetector(
                  onLongPress: () { if (!isSelected) setState(() => _selectedVerses.add(vNum)); _showActionMenu(); },
                  onTap: () => setState(() => isSelected ? _selectedVerses.remove(vNum) : _selectedVerses.add(vNum)),
                  child: Container(
                    color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(text: TextSpan(style: TextStyle(color: Colors.black, fontSize: _fontSize, height: 1.5), children: [
                          TextSpan(text: "$vNum. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          TextSpan(text: _cleanText(v['text'])),
                        ])),
                        if (_verseNotesMap.containsKey(vNum)) Padding(padding: const EdgeInsets.only(top: 8), child: InkWell(onTap: () => _showNoteSelection(_verseNotesMap[vNum]!), child: const Text("📝", style: TextStyle(fontSize: 25)))),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// 👇 CLASS NAVIGASI (FULL UI DENGAN PEMISAHAN PERJANJIAN LAMA & BARU) 👇
class _NavSheet extends StatefulWidget {
  final List<BibleBook> allBooks; final Database db; final String currentVersion; final Function(String) onVersionChange; final Function(int, int, int) onSelectionComplete;
  const _NavSheet({required this.allBooks, required this.db, required this.currentVersion, required this.onVersionChange, required this.onSelectionComplete});
  @override State<_NavSheet> createState() => _NavSheetState();
}

class _NavSheetState extends State<_NavSheet> {
  BibleBook? selBook; int? selChapter; List<int> chapters = []; List<int> verses = [];
  void _getChapters(BibleBook b) async {
    final res = await widget.db.rawQuery("SELECT DISTINCT chapter FROM verses WHERE book_number = ? ORDER BY chapter ASC", [b.bookNumber]);
    setState(() { selBook = b; chapters = res.map((e) => e['chapter'] as int).toList(); selChapter = null; });
  }
  void _getVerses(int c) async {
    final res = await widget.db.rawQuery("SELECT verse FROM verses WHERE book_number = ? AND chapter = ?", [selBook!.bookNumber, c]);
    setState(() { selChapter = c; verses = res.map((e) => e['verse'] as int).toList(); });
  }
  @override 
  Widget build(BuildContext context) => SafeArea(bottom: false, child: _buildContent());

  Widget _buildContent() {
    if (selChapter != null) return _buildGrid("Ayat: ${selBook!.name} $selChapter", verses, (v) { widget.onSelectionComplete(selBook!.bookNumber, selChapter!, v); Navigator.pop(context); }, () => setState(() => selChapter = null));
    if (selBook != null) return _buildGrid("Pasal: ${selBook!.name}", chapters, (c) => _getVerses(c), () => setState(() => selBook = null));
    List<BibleBook> pl = widget.allBooks.where((b) => b.bookNumber < 470).toList();
    List<BibleBook> pb = widget.allBooks.where((b) => b.bookNumber >= 470).toList();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.all(16), color: Colors.indigo[50], child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text("Versi:", style: TextStyle(fontWeight: FontWeight.bold)),
        DropdownButton<String>(value: widget.currentVersion, items: const [DropdownMenuItem(value: "TB.SQLite3", child: Text("TB")), DropdownMenuItem(value: "TJL.SQLite3", child: Text("TJL"))], onChanged: (v) => widget.onVersionChange(v!)),
      ])),
      Flexible(child: ListView(shrinkWrap: true, children: [_header("PERJANJIAN LAMA", Colors.pink), _kitabGrid(pl), const Divider(), _header("PERJANJIAN BARU", Colors.blue), _kitabGrid(pb)])),
    ]);
  }

  Widget _buildGrid(String t, List<int> items, Function(int) onTap, VoidCallback onBack) => Column(mainAxisSize: MainAxisSize.min, children: [AppBar(title: Text(t, style: const TextStyle(fontSize: 16, color: Colors.black)), leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: onBack), backgroundColor: Colors.transparent, elevation: 0), Flexible(child: GridView.builder(shrinkWrap: true, padding: const EdgeInsets.all(12), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 60, childAspectRatio: 1.2, mainAxisSpacing: 6, crossAxisSpacing: 6), itemCount: items.length, itemBuilder: (ctx, i) => InkWell(onTap: () => onTap(items[i]), child: Container(alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: Text("${items[i]}", style: const TextStyle(fontWeight: FontWeight.bold))))))]);
  Widget _header(String t, Color c) => Padding(padding: const EdgeInsets.all(12), child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12)));
  Widget _kitabGrid(List<BibleBook> books) => GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 12), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 68, childAspectRatio: 1.9, mainAxisSpacing: 6, crossAxisSpacing: 6), itemCount: books.length, itemBuilder: (ctx, i) => InkWell(onTap: () => _getChapters(books[i]), child: Container(alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)), child: Text(books[i].shortName.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))));
}