import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart'; 
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

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
  
  // Default ke 10 (Kejadian) sesuai database Anda
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
    
    // Muat riwayat bacaan terakhir (Aman, default kembali ke 10)
    _currentBookNum = _prefs.getInt('LAST_BOOK_NUM') ?? 10; 
    _currentChapter = _prefs.getInt('LAST_CHAPTER') ?? 1;

    await _loadDatabase();
  }

  // Simpan riwayat bacaan
  void _saveLastPosition() {
    _prefs.setInt('LAST_BOOK_NUM', _currentBookNum);
    _prefs.setInt('LAST_CHAPTER', _currentChapter);
  }

  Future<void> _loadDatabase() async {
    setState(() => _isLoading = true);
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
  }

  Future<void> _loadContent({int? scrollToVerse}) async {
    if (_db == null) return;

    final verseData = await _db!.query('verses', 
        where: 'book_number = ? AND chapter = ?', 
        whereArgs: [_currentBookNum, _currentChapter],
        orderBy: 'verse ASC');
        
    final storyData = await _db!.query('stories',
        where: 'book_number = ? AND chapter = ?',
        whereArgs: [_currentBookNum, _currentChapter],
        orderBy: 'verse ASC, order_if_several ASC');

    _perikopMap.clear();
    for (var s in storyData) {
      int vNum = s['verse'] as int;
      String title = s['title'].toString();
      if (!_perikopMap.containsKey(vNum)) {
        _perikopMap[vNum] = [];
      }
      _perikopMap[vNum]!.add(title);
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
    
    // Amankan pengambilan nama kitab
    String currentBookName = _allBooks.firstWhere(
      (b) => b.bookNumber == _currentBookNum, 
      orElse: () => _allBooks.first
    ).name;
    
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
          } catch (e) { /* ignore */ }
        }
      }
    }
  }

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
                  onTap: () { Navigator.pop(context); _openNote(key); },
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
          existingKey: key,
          db: _db!,
          allBooks: _allBooks,
        )
      )).then((_) => _loadContent());
    }
  }

  void _showNavigation() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true, 
      barrierLabel: "Tutup Navigasi",
      barrierColor: Colors.black.withOpacity(0.5), 
      transitionDuration: const Duration(milliseconds: 300), 
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(25)),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: _NavSheet(
                allBooks: _allBooks,
                db: _db!,
                onSelectionComplete: (bookNum, chapter, verse) {
                  setState(() { _currentBookNum = bookNum; _currentChapter = chapter; });
                  _saveLastPosition(); 
                  _loadContent(scrollToVerse: verse);
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1), 
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
    );
  }

  void _showActionMenu() {
    if (_selectedVerses.isEmpty) return;
    List<int> sorted = _selectedVerses.toList()..sort();
    
    // Aman dari crash
    String bookName = _allBooks.firstWhere(
      (b) => b.bookNumber == _currentBookNum,
      orElse: () => _allBooks.first
    ).name;
    
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
              Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(
                nas: nas, 
                prefs: _prefs,
                db: _db!,
                allBooks: _allBooks,
              ))).then((_) => _loadContent()); 
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
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Disalin ke papan klip")));
            }
          ),
        ]
      )
    );
  }

  Widget _buildPerikopItem(String title) {
    if (!title.contains("<x>")) {
      return Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: Colors.black),
      );
    }

    List<InlineSpan> spans = [];
    final regex = RegExp(r'<x>(.*?)</x>');

    title.splitMapJoin(
      regex,
      onMatch: (Match m) {
        String rawRef = m.group(1) ?? ""; 
        final refData = RegExp(r'(\d+)\s+(\d+):(\d+)').firstMatch(rawRef);
        
        if (refData != null) {
          int bNum = int.parse(refData.group(1)!);
          int chap = int.parse(refData.group(2)!);
          int vStart = int.parse(refData.group(3)!);
          
          String bookShortName = bNum.toString();
          try {
            bookShortName = _allBooks.firstWhere((b) => b.bookNumber == bNum).shortName;
          } catch (e) {}
          
          String displayText = rawRef.replaceFirst(bNum.toString(), bookShortName);

          spans.add(TextSpan(
            text: displayText,
            style: const TextStyle(
              color: Colors.blue, 
              fontWeight: FontWeight.w600, 
              decoration: TextDecoration.underline
            ),
            recognizer: TapGestureRecognizer()..onTap = () {
              setState(() { _currentBookNum = bNum; _currentChapter = chap; });
              _saveLastPosition(); 
              _loadContent(scrollToVerse: vStart);
            },
          ));
        } else {
          spans.add(TextSpan(text: rawRef)); 
        }
        return "";
      },
      onNonMatch: (String text) {
        spans.add(TextSpan(text: text));
        return "";
      },
    );

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: const TextStyle(fontSize: 15, color: Colors.black, fontStyle: FontStyle.italic),
        children: spans,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Memastikan tidak akan pernah error saat awal mula load database
    String bookName = _allBooks.isEmpty 
        ? "" 
        : _allBooks.firstWhere(
            (b) => b.bookNumber == _currentBookNum, 
            orElse: () => _allBooks.first
          ).name;
    
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
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (c) => NoteListPage(
                prefs: _prefs,
                db: _db!,
                allBooks: _allBooks,
              )
            )).then((res) {
              if (res != null && res is Map) {
                setState(() { 
                  _currentBookNum = res['book_number']; 
                  _currentChapter = res['chapter']; 
                }); 
                _saveLastPosition(); 
                _loadContent(scrollToVerse: res['verse']);
              } else {
                _loadContent(); 
              }
            })
          ),
          
          IconButton(
            icon: const Icon(Icons.search), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (c) => SearchPage(
                db: _db!, 
                allBooks: _allBooks,
                currentBookNum: _currentBookNum,
              )
            )).then((res) {
              if (res != null) { 
                setState(() { 
                  _currentBookNum = res['book_number']; 
                  _currentChapter = res['chapter']; 
                }); 
                _saveLastPosition(); 
                _loadContent(scrollToVerse: res['verse']); 
              }
            })
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : ListView.builder(
            controller: _scrollController,
            itemCount: _verses.length,
            itemBuilder: (context, i) {
              final v = _verses[i]; 
              final vNum = v['verse'] as int; 
              final isSelected = _selectedVerses.contains(vNum); 
              final noteKeys = _verseNotesMap[vNum];
              final perikopList = _perikopMap[vNum];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (perikopList != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 25, 20, 10),
                      child: Column(
                        children: perikopList.map((title) => Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: _buildPerikopItem(title),
                        )).toList(),
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
                          if (noteKeys != null && noteKeys.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: InkWell(
                                onTap: () => _showNoteSelection(noteKeys),
                                child: const Padding(padding: EdgeInsets.all(4.0), child: Text("📝", style: TextStyle(fontSize: 28))),
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

// =========================================================================
// UI NAVIGATION SHEET (RESPONSIF UNTUK HP KECIL & TABLET)
// =========================================================================
class _NavSheet extends StatefulWidget {
  final List<BibleBook> allBooks;
  final Database db;
  final Function(int bookNum, int chapter, int verse) onSelectionComplete;
  const _NavSheet({required this.allBooks, required this.db, required this.onSelectionComplete});
  @override State<_NavSheet> createState() => _NavSheetState();
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
    return SafeArea(
      bottom: false, 
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (selChapter != null) {
      return _buildGrid(
        "Ayat: ${selBook!.name} $selChapter", verses, 
        (v) { widget.onSelectionComplete(selBook!.bookNumber, selChapter!, v); Navigator.pop(context); }, 
        () => setState(() => selChapter = null)
      );
    }
    
    if (selBook != null) {
      return _buildGrid(
        "Pasal: ${selBook!.name}", chapters, 
        (c) => _getVerses(c), 
        () => setState(() => selBook = null)
      );
    }

    List<BibleBook> pl = widget.allBooks.where((b) => b.bookNumber < 470).toList();
    List<BibleBook> pb = widget.allBooks.where((b) => b.bookNumber >= 470).toList();
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // FIX: Menggunakan Flexible, bukan Expanded
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              _header("PERJANJIAN LAMA", const Color(0xFFE91E63)), 
              _kitabGrid(pl), 
              
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6.0),
                child: Divider(color: Color(0xFFEEEEEE), thickness: 1.5, height: 10),
              ),
              
              _header("PERJANJIAN BARU", const Color(0xFF03A9F4)), 
              _kitabGrid(pb), 
              const SizedBox(height: 10), 
            ]
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.pop(context), 
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Center(
              child: Container(
                width: 40, height: 4, 
                decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(10))
              )
            ),
          ),
        )
      ],
    );
  }

  Widget _buildGrid(String title, List<int> items, Function(int) onTap, VoidCallback onBack) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppBar(
        title: Text(title, style: const TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.bold)), 
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: onBack), 
        backgroundColor: Colors.transparent, 
        elevation: 0,
        toolbarHeight: 48, 
      ),
      Flexible(
        child: GridView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), 
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 60, 
            childAspectRatio: 1.2,  
            mainAxisSpacing: 6,     
            crossAxisSpacing: 6     
          ), 
          itemCount: items.length, 
          itemBuilder: (ctx, i) => InkWell(
            onTap: () => onTap(items[i]), 
            child: Container(
              alignment: Alignment.center, 
              decoration: BoxDecoration(
                color: Colors.white, 
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300)
              ), 
              child: Text(
                "${items[i]}", 
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14) 
              )
            )
          )
        )
      ),
    ]
  );

  Widget _header(String t, Color c) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8), 
    child: Text(
      t, 
      style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5)
    )
  );

  Widget _kitabGrid(List<BibleBook> books) => GridView.builder(
    shrinkWrap: true, 
    physics: const NeverScrollableScrollPhysics(), 
    padding: const EdgeInsets.symmetric(horizontal: 12), 
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 68, 
      childAspectRatio: 1.9,  
      mainAxisSpacing: 6,     
      crossAxisSpacing: 6     
    ), 
    itemCount: books.length, 
    itemBuilder: (ctx, i) => InkWell(
      onTap: () => _getChapters(books[i]), 
      borderRadius: BorderRadius.circular(6),
      child: Container(
        alignment: Alignment.center, 
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(6), 
          border: Border.all(color: Colors.grey.shade300, width: 1.0) 
        ), 
        child: Text(
          books[i].shortName.toUpperCase(), 
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Colors.black) 
        )
      )
    )
  );
}