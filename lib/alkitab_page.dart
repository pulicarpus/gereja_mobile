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

  // Fungsi untuk mendapatkan jumlah Pasal di sebuah Kitab
  Future<int> _getMaxChapter(int bookId) async {
    var res = await _db!.rawQuery('SELECT MAX(chapter) as max FROM verses WHERE book_number = ?', [bookId]);
    return res.first['max'] as int? ?? 1;
  }

  // Fungsi untuk mendapatkan jumlah Ayat di sebuah Pasal
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
          _scrollController.jumpTo((scrollToVerse - 1) * 80.0); 
        });
      }
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = "Error: $e"; });
    }
  }

  void _showBiblePicker() async {
    int tempBookId = _bookId;
    int tempChapter = _chapter;
    int currentStep = 0; 
    int maxChapters = await _getMaxChapter(tempBookId);
    int maxVerses = await _getMaxVerse(tempBookId, tempChapter);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      currentStep > 0 
                        ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setModalState(() => currentStep--))
                        : const SizedBox(width: 48),
                      Text(currentStep == 0 ? "Pilih Kitab" : currentStep == 1 ? "Pilih Pasal" : "Pilih Ayat", 
                           style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: currentStep == 0
                        ? _buildBookGrid(setModalState, (id) async {
                            tempBookId = id;
                            maxChapters = await _getMaxChapter(id);
                            setModalState(() => currentStep = 1);
                          })
                        : currentStep == 1
                            ? _buildNumberGrid(maxChapters, (n) async {
                                tempChapter = n;
                                maxVerses = await _getMaxVerse(tempBookId, n);
                                setModalState(() => currentStep = 2);
                              })
                            : _buildNumberGrid(maxVerses, (n) {
                                setState(() { _bookId = tempBookId; _chapter = tempChapter; _isLoading = true; });
                                _loadData(scrollToVerse: n);
                                Navigator.pop(context);
                              }),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBookGrid(StateSetter setModalState, Function(int) onSelect) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 2.2, mainAxisSpacing: 8, crossAxisSpacing: 8,
      ),
      itemCount: _allBooks.length,
      itemBuilder: (context, i) {
        return InkWell(
          onTap: () => onSelect(_allBooks[i]['book_number']),
          child: Container(
            decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Text(_allBooks[i]['short_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  Widget _buildNumberGrid(int max, Function(int) onSelect) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5, mainAxisSpacing: 8, crossAxisSpacing: 8,
      ),
      itemCount: max,
      itemBuilder: (context, i) {
        return InkWell(
          onTap: () => onSelect(i + 1),
          child: Container(
            decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Text("${i + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
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
          onTap: _showBiblePicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("$_bookName $_chapter", style: const TextStyle(fontSize: 16)),
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
            icon: const Icon(Icons.translate, color: Colors.white),
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