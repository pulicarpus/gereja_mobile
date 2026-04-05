import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
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
  Map<int, String> _perikopMap = {}; 
  List<BibleBook> _allBooks = [];
  Set<int> _selectedVerses = {};
  Map<int, List<String>> _verseNotesMap = {}; 
  final ScrollController _scrollController = ScrollController();
  
  String _currentVersion = "TB.SQLite3"; 
  int _currentBookNum = 10; 
  int _currentChapter = 1;
  bool _isLoading = true;
  late SharedPreferences _prefs;

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
    await _loadDatabase();
  }

  Future<void> _loadDatabase() async {
    setState(() => _isLoading = true);
    var dbPath = await getDatabasesPath();
    String path = p.join(dbPath, _currentVersion);
    
    ByteData data = await rootBundle.load("assets/$_currentVersion");
    List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await File(path).writeAsBytes(bytes, flush: true);
    
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
  }

  Future<void> _loadContent({int? scrollToVerse}) async {
    if (_db == null) return;

    final verseData = await _db!.query('verses', 
        where: 'book_number = ? AND chapter = ?', 
        whereArgs: [_currentBookNum, _currentChapter],
        orderBy: 'verse ASC');
        
    final storyData = await _db!.query('stories',
        where: 'book_number = ? AND chapter = ?',
        whereArgs: [_currentBookNum, _currentChapter]);

    _perikopMap.clear();
    for (var s in storyData) {
      _perikopMap[s['verse'] as int] = s['title'].toString();
    }

    _verses = verseData;
    await _syncNotes(); 
    
    setState(() {
      _isLoading = false;
      _selectedVerses.clear();
    });

    if (scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          double position = (scrollToVerse - 1) * 110.0; 
          _scrollController.animateTo(position, duration: const Duration(milliseconds: 600), curve: Curves.easeOut);
        }
      });
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
      if (rawData != null) {
        String nas = rawData.split("~|~")[0];
        if (nas.startsWith(prefix)) {
          try {
            String versePart = nas.split(":")[1];
            int lastVerse = int.parse(versePart.split(RegExp(r'[-,]')).last);
            if (!_verseNotesMap.containsKey(lastVerse)) _verseNotesMap[lastVerse] = [];
            _verseNotesMap[lastVerse]!.add(key);
          } catch (e) { print(e); }
        }
      }
    }
  }

  // FUNGSI FLOATING UNTUK MEMILIH CATATAN
  void _showNoteSelection(List<String> keys) {
    if (keys.length == 1) {
      _openNote(keys[0]);
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("Pilih Catatan", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ),
          const Divider(),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: keys.length,
              itemBuilder: (context, index) {
                String key = keys[index];
                String raw = _prefs.getString(key) ?? "";
                String nas = raw.split("~|~")[0];
                String isi = raw.split("~|~").length > 1 ? raw.split("~|~")[1] : "";
                return ListTile(
                  leading: const Text("📝", style: TextStyle(fontSize: 20)),
                  title: Text(nas, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(isi, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(context);
                    _openNote(key);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _openNote(String key) {
    String? raw = _prefs.getString(key);
    if (raw != null) {
      Navigator.push(context, MaterialPageRoute(
        builder: (c) => NoteEditorPage(
          nas: raw.split("~|~")[0], 
          prefs: _prefs, 
          existingKey: key
        )
      )).then((_) => _loadContent());
    }
  }

  void _showNavigation() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => _NavSheet(
        allBooks: _allBooks,
        db: _db!,
        onSelectionComplete: (bookNum, chapter, verse) {
          setState(() { _currentBookNum = bookNum; _currentChapter = chapter; });
          _loadContent(scrollToVerse: verse);
        },
      ),
    );
  }

  void _showActionMenu() {
    if (_selectedVerses.isEmpty) return;
    List<int> sorted = _selectedVerses.toList()..sort();
    String bookName = _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    String verseRange = sorted.length > 1 && (sorted.last - sorted.first == sorted.length - 1)
        ? "${sorted.first}-${sorted.last}"
        : sorted.join(",");
    String nas = "$bookName $_currentChapter:$verseRange";
    
    showModalBottomSheet(
      context: context, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), 
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min, 
        children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(nas, style: const TextStyle(fontWeight: FontWeight.bold))),
          ListTile(
            leading: const Icon(Icons.add_comment, color: Colors.blue), 
            title: const Text("Buat Catatan Baru"), 
            onTap: () { 
              Navigator.pop(context); 
              Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: nas, prefs: _prefs))).then((_) => _loadContent()); 
            }
          ),
          ListTile(
            leading: const Icon(Icons.copy), 
            title: const Text("Salin Ayat"), 
            onTap: () { 
              String fullText = "$nas\n";
              for (var vNum in sorted) {
                var vData = _verses.firstWhere((element) => element['verse'] == vNum);
                fullText += "$vNum. ${_cleanText(vData['text'])}\n";
              }
              Clipboard.setData(ClipboardData(text: fullText)); 
              Navigator.pop(context); 
              setState(() => _selectedVerses.clear()); 
            }
          ),
        ]
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    String bookName = _allBooks.isEmpty ? "" : _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
        title: InkWell(
          onTap: _showNavigation, 
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text("$bookName $_currentChapter", style: const TextStyle(fontSize: 18)),
            const Icon(Icons.arrow_drop_down),
          ]),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.event_note), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => NoteListPage(prefs: _prefs))).then((_) => _loadContent())
          ),
          IconButton(
            icon: const Icon(Icons.search), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => SearchPage(db: _db!, allBooks: _allBooks))).then((res) {
              if (res != null) { setState(() { _currentBookNum = res['book_number']; _currentChapter = res['chapter']; }); _loadContent(); }
            })
          ),
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        controller: _scrollController,
        itemCount: _verses.length,
        itemBuilder: (context, i) {
          final v = _verses[i]; 
          final vNum = v['verse'] as int; 
          final isSelected = _selectedVerses.contains(vNum); 
          final noteKeys = _verseNotesMap[vNum];
          final perikop = _perikopMap[vNum];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // PERBAIKAN TAMPILAN PERIKOP: TENGAH, BESAR, BOLD, BIRU MUDA
              if (perikop != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 25, 16, 12),
                  child: Text(
                    perikop, 
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      fontSize: 20, 
                      color: Colors.blue[300], // Biru Muda
                      height: 1.3
                    ),
                  ),
                ),
              GestureDetector(
                onLongPress: () { if (!isSelected) setState(() => _selectedVerses.add(vNum)); _showActionMenu(); },
                onTap: () => setState(() => isSelected ? _selectedVerses.remove(vNum) : _selectedVerses.add(vNum)),
                child: Container(
                  color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent, 
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(text: TextSpan(style: const TextStyle(color: Colors.black, fontSize: 18, height: 1.5), children: [
                        TextSpan(text: "$vNum. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                        TextSpan(text: _cleanText(v['text'])),
                      ])),
                      
                      // HANYA SATU IKON CATATAN MESKIPUN BANYAK CATATAN
                      if (noteKeys != null && noteKeys.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: InkWell(
                            onTap: () => _showNoteSelection(noteKeys),
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Text("📝", style: TextStyle(fontSize: 28)),
                            ),
                          ),
                        ),
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

class _NavSheet extends StatefulWidget {
  final List<BibleBook> allBooks;
  final Database db;
  final Function(int bookNum, int chapter, int verse) onSelectionComplete;
  const _NavSheet({required this.allBooks, required this.db, required this.onSelectionComplete});
  @override
  State<_NavSheet> createState() => _NavSheetState();
}

class _NavSheetState extends State<_NavSheet> {
  BibleBook? selBook;
  int? selChapter;
  List<int> chapters = [];
  List<int> verses = [];

  void _getChapters(BibleBook book) async {
    final res = await widget.db.rawQuery("SELECT DISTINCT chapter FROM verses WHERE book_number = ? ORDER BY chapter ASC", [book.bookNumber]);
    setState(() { selBook = book; chapters = res.map((e) => e['chapter'] as int).toList(); selChapter = null; });
  }

  void _getVerses(int chapter) async {
    final res = await widget.db.rawQuery("SELECT verse FROM verses WHERE book_number = ? AND chapter = ? ORDER BY verse ASC", [selBook!.bookNumber, chapter]);
    setState(() { selChapter = chapter; verses = res.map((e) => e['verse'] as int).toList(); });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.9, maxChildSize: 0.95,
      builder: (_, controller) {
        if (selChapter != null) {
          return _buildGrid(controller, "Ayat: ${selBook!.name} $selChapter", verses, (v) {
            widget.onSelectionComplete(selBook!.bookNumber, selChapter!, v);
            Navigator.pop(context);
          }, () => setState(() => selChapter = null));
        }
        if (selBook != null) {
          return _buildGrid(controller, "Pasal: ${selBook!.name}", chapters, (c) => _getVerses(c), () => setState(() => selBook = null));
        }

        List<BibleBook> pl = widget.allBooks.where((b) => b.bookNumber < 470).toList();
        List<BibleBook> pb = widget.allBooks.where((b) => b.bookNumber >= 470).toList();

        return ListView(controller: controller, children: [
          const SizedBox(height: 10),
          Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
          _header("PERJANJIAN LAMA", Colors.pink),
          _kitabGrid(pl),
          const Divider(),
          _header("PERJANJIAN BARU", Colors.blue),
          _kitabGrid(pb),
          const SizedBox(height: 50),
        ]);
      },
    );
  }

  Widget _buildGrid(ScrollController c, String title, List<int> items, Function(int) onTap, VoidCallback onBack) => Column(children: [
    AppBar(title: Text(title, style: const TextStyle(fontSize: 16, color: Colors.black)), leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: onBack), backgroundColor: Colors.transparent, elevation: 0),
    Expanded(child: GridView.builder(controller: c, padding: const EdgeInsets.all(15), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 10, crossAxisSpacing: 10), 
      itemCount: items.length, itemBuilder: (ctx, i) => InkWell(onTap: () => onTap(items[i]), child: Container(alignment: Alignment.center, decoration: BoxDecoration(color: Colors.indigo[50], borderRadius: BorderRadius.circular(10)), child: Text("${items[i]}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))))),
  ]);

  Widget _header(String t, Color c) => Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 14)));
  Widget _kitabGrid(List<BibleBook> books) => GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 12), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, childAspectRatio: 1.8, mainAxisSpacing: 8, crossAxisSpacing: 8), 
    itemCount: books.length, itemBuilder: (ctx, i) => InkWell(onTap: () => _getChapters(books[i]), child: Container(alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)), child: Text(books[i].shortName.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)))));
}