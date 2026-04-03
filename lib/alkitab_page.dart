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
  String _errorMessage = "";

  String _currentVersion = "TB";
  final Map<String, String> _bibleFiles = {
    "TB": "TB.SQLite3",
    "TL": "TJL.SQLite3",
  };

  int _bookId = 10; 
  int _chapter = 1;
  String _bookName = "Kejadian";
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  String _shortenBookName(String name) {
    return name
      .replaceAll("Surat Paulus Yang Pertama Kepada Jemaat Di ", "1 ")
      .replaceAll("Surat Paulus Yang Kedua Kepada Jemaat Di ", "2 ")
      .replaceAll("Surat Paulus Kepada Jemaat Di ", "")
      .replaceAll("Surat Kepada Orang ", "")
      .replaceAll("Surat Paulus Kepada ", "")
      .replaceAll("Surat Yang Pertama Dari ", "1 ")
      .replaceAll("Surat Yang Kedua Dari ", "2 ")
      .replaceAll("Surat Yang Ketiga Dari ", "3 ")
      .replaceAll("Surat Dari ", "")
      .replaceAll("Injil Menurut ", "")
      .replaceAll("Kisah Para ", "")
      .trim();
  }

  Future<void> _initDatabase() async {
    try {
      setState(() => _isLoading = true);
      var dbPath = await getDatabasesPath();
      String fileName = _bibleFiles[_currentVersion] ?? "TB.SQLite3";
      var path = p.join(dbPath, fileName);

      if (!(await databaseExists(path))) {
        await Directory(p.dirname(path)).create(recursive: true);
        ByteData data = await rootBundle.load("assets/$fileName");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      }

      _db = await openDatabase(path, readOnly: true);
      await _loadBooks();
      await _loadData();
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = "Error DB: $e"; });
    }
  }

  Future<void> _loadBooks() async {
    if (_db == null) return;
    final List<Map<String, dynamic>> books = await _db!.query('books', orderBy: 'book_number ASC');
    setState(() => _allBooks = books);
  }

  Future<int> _getMaxChapter(int bookId) async {
    var res = await _db!.rawQuery('SELECT MAX(chapter) as max FROM verses WHERE book_number = ?', [bookId]);
    return res.first['max'] as int? ?? 1;
  }

  Future<int> _getMaxVerse(int bookId, int chapter) async {
    var res = await _db!.rawQuery('SELECT MAX(verse) as max FROM verses WHERE book_number = ? AND chapter = ?', [bookId, chapter]);
    return res.first['max'] as int? ?? 1;
  }

  Future<void> _loadData({int? scrollToVerse}) async {
    if (_db == null) return;
    try {
      final List<Map<String, dynamic>> verses = await _db!.query(
        'verses',
        where: 'book_number = ? AND chapter = ?',
        whereArgs: [_bookId, _chapter],
        orderBy: 'verse ASC',
      );

      Map<int, String> storyMap = {};
      if (_currentVersion == "TB") {
        try {
          final List<Map<String, dynamic>> stories = await _db!.query(
            'stories',
            where: 'book_number = ? AND chapter = ?',
            whereArgs: [_bookId, _chapter],
          );
          for (var s in stories) { storyMap[s['verse']] = s['title']; }
        } catch (_) {}
      }

      setState(() {
        _verses = verses;
        _pericopes = storyMap;
        _bookName = _allBooks.firstWhere((b) => b['book_number'] == _bookId)['long_name'];
        _isLoading = false;
      });

      if (scrollToVerse != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollController.jumpTo((scrollToVerse - 1) * 85.0); 
        });
      }
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = "Error: $e"; });
    }
  }

  // --- TAMPILAN PICKER DARI ATAS (FULL SCREEN DIALOG) ---
  void _showTopPicker() async {
    int tempBookId = _bookId;
    int tempChapter = _chapter;
    int currentStep = 0; // 0: Kitab, 1: Pasal, 2: Ayat
    int maxChapters = await _getMaxChapter(tempBookId);
    int maxVerses = await _getMaxVerse(tempBookId, tempChapter);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Close",
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Pisahkan PL dan PB
            List<Map<String, dynamic>> pl = _allBooks.where((b) => b['book_number'] <= 39).toList();
            List<Map<String, dynamic>> pb = _allBooks.where((b) => b['book_number'] > 39).toList();

            return Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                leading: currentStep > 0 
                  ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setModalState(() => currentStep--))
                  : IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                title: Text(currentStep == 0 ? "Pilih Kitab" : currentStep == 1 ? "Pilih Pasal" : "Pilih Ayat"),
              ),
              body: Column(
                children: [
                  Expanded(
                    child: currentStep == 0
                        ? ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              _buildSectionTitle("PERJANJIAN LAMA"),
                              _buildBookGrid(pl, setModalState, (id) async {
                                tempBookId = id;
                                maxChapters = await _getMaxChapter(id);
                                setModalState(() => currentStep = 1);
                              }),
                              const SizedBox(height: 20),
                              _buildSectionTitle("PERJANJIAN BARU"),
                              _buildBookGrid(pb, setModalState, (id) async {
                                tempBookId = id;
                                maxChapters = await _getMaxChapter(id);
                                setModalState(() => currentStep = 1);
                              }),
                            ],
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 5, mainAxisSpacing: 10, crossAxisSpacing: 10,
                            ),
                            itemCount: currentStep == 1 ? maxChapters : maxVerses,
                            itemBuilder: (context, i) {
                              return InkWell(
                                onTap: () async {
                                  if (currentStep == 1) {
                                    tempChapter = i + 1;
                                    maxVerses = await _getMaxVerse(tempBookId, tempChapter);
                                    setModalState(() => currentStep = 2);
                                  } else {
                                    setState(() { _bookId = tempBookId; _chapter = tempChapter; _isLoading = true; });
                                    _loadData(scrollToVerse: i + 1);
                                    Navigator.pop(context);
                                  }
                                },
                                child: Container(
                                  decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                  alignment: Alignment.center,
                                  child: Text("${i + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween(begin: const Offset(0, -1), end: const Offset(0, 0)).animate(anim1),
          child: child,
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
    );
  }

  Widget _buildBookGrid(List<Map<String, dynamic>> books, StateSetter setModalState, Function(int) onSelect) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 2.4, mainAxisSpacing: 8, crossAxisSpacing: 8,
      ),
      itemCount: books.length,
      itemBuilder: (context, i) {
        String displayTitle = _shortenBookName(books[i]['long_name']);
        return InkWell(
          onTap: () => onSelect(books[i]['book_number']),
          child: Container(
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
            alignment: Alignment.center,
            child: Text(displayTitle, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showTopPicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("${_shortenBookName(_bookName)} $_chapter", style: const TextStyle(fontSize: 16)),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          DropdownButton<String>(
            value: _currentVersion,
            dropdownColor: Colors.indigo,
            underline: const SizedBox(),
            icon: const Icon(Icons.compare_arrows, color: Colors.white),
            onChanged: (v) {
              if (v != null) { setState(() { _currentVersion = v; _db = null; }); _initDatabase(); }
            },
            items: ["TB", "TL"].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(color: Colors.white)))).toList(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _verses.length,
              itemBuilder: (context, index) {
                final v = _verses[index];
                final String? pTitle = _pericopes[v['verse']];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pTitle != null && _currentVersion == "TB")
                      Padding(
                        padding: const EdgeInsets.only(top: 15, bottom: 5),
                        child: Text(pTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, color: Colors.brown)),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.6),
                          children: [
                            TextSpan(text: "${v['verse']} ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 14)),
                            TextSpan(text: v['text'].toString().replaceAll(RegExp(r'<[^>]*>'), '')),
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