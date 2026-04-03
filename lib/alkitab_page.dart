import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

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
  
  Set<int> _selectedVerses = {}; 
  Map<int, String> _userNotes = {};

  String _currentVersion = "TB";
  int _bookId = 10; 
  int _chapter = 1;
  String _bookName = "Kejadian";
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  // --- FUNGSI PEMBERSIH TEKS (AGAR HURUF GAK PENTING HILANG) ---
  String _cleanText(String text) {
    if (text.isEmpty) return "";
    return text
        .replaceAll(RegExp(r'<[^>]*>'), '') // Hapus tag html <...>
        .replaceAll(RegExp(r'\\f.*?\\f'), '') // Hapus tag \f...\f
        .replaceAll(RegExp(r'\\.*?\\'), '') // Hapus tag backslash lainnya
        .trim();
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
      String fileName = _currentVersion == "TB" ? "TB.SQLite3" : "TJL.SQLite3";
      var path = p.join(dbPath, fileName);

      if (!(await databaseExists(path))) {
        await Directory(p.dirname(path)).create(recursive: true);
        ByteData data = await rootBundle.load("assets/$fileName");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      }

      _db = await openDatabase(path);
      await _db!.execute('CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, book_id INTEGER, chapter INTEGER, verse INTEGER, content TEXT, date TEXT)');
      
      await _loadBooks();
      await _loadData();
    } catch (e) {
      print("Error Init: $e");
    }
  }

  Future<void> _loadBooks() async {
    final books = await _db!.query('books', orderBy: 'book_number ASC');
    setState(() => _allBooks = books);
  }

  Future<void> _loadData({int? scrollToVerse}) async {
    setState(() => _isLoading = true);
    final verses = await _db!.query('verses', where: 'book_number = ? AND chapter = ?', whereArgs: [_bookId, _chapter]);
    
    final notesData = await _db!.query('notes', where: 'book_id = ? AND chapter = ?', whereArgs: [_bookId, _chapter]);
    Map<int, String> tempNotes = {};
    for (var n in notesData) { tempNotes[n['verse'] as int] = n['content'] as String; }

    Map<int, String> storyMap = {};
    if (_currentVersion == "TB") {
      try {
        final stories = await _db!.query('stories', where: 'book_number = ? AND chapter = ?', whereArgs: [_bookId, _chapter]);
        for (var s in stories) { storyMap[s['verse']] = s['title']; }
      } catch (_) {}
    }

    setState(() {
      _verses = verses;
      _pericopes = storyMap;
      _userNotes = tempNotes;
      if (_allBooks.isNotEmpty) {
        _bookName = _allBooks.firstWhere((b) => b['book_number'] == _bookId)['long_name'];
      }
      _isLoading = false;
      _selectedVerses.clear();
    });

    if (scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.jumpTo((scrollToVerse - 1) * 85.0);
      });
    }
  }

  // --- PICKER DARI ATAS ---
  void _showTopPicker() async {
    int tempBookId = _bookId;
    int tempChapter = _chapter;
    int currentStep = 0; 
    
    // Fungsi lokal untuk ambil max dari DB
    Future<int> _getMax(String col, int bid, [int? chap]) async {
      String q = chap == null ? 'SELECT MAX($col) as m FROM verses WHERE book_number = ?' : 'SELECT MAX($col) as m FROM verses WHERE book_number = ? AND chapter = ?';
      var r = await _db!.rawQuery(q, chap == null ? [bid] : [bid, chap]);
      return r.first['m'] as int? ?? 1;
    }

    int maxChapters = await _getMax('chapter', tempBookId);
    int maxVerses = await _getMax('verse', tempBookId, tempChapter);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Tutup",
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, a1, a2) {
        return StatefulBuilder(
          builder: (context, setST) {
            List<Map<String, dynamic>> pl = _allBooks.where((b) => b['book_number'] <= 39).toList();
            List<Map<String, dynamic>> pb = _allBooks.where((b) => b['book_number'] > 39).toList();

            return Scaffold(
              appBar: AppBar(
                backgroundColor: Colors.indigo,
                title: Text(currentStep == 0 ? "Pilih Kitab" : currentStep == 1 ? "Pilih Pasal" : "Pilih Ayat"),
                leading: currentStep > 0 
                  ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setST(() => currentStep--))
                  : IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ),
              body: currentStep == 0 
                ? ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Text("PERJANJIAN LAMA", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      _gridKitab(pl, (id) async {
                        tempBookId = id;
                        maxChapters = await _getMax('chapter', id);
                        setST(() => currentStep = 1);
                      }),
                      const SizedBox(height: 20),
                      const Text("PERJANJIAN BARU", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      _gridKitab(pb, (id) async {
                        tempBookId = id;
                        maxChapters = await _getMax('chapter', id);
                        setST(() => currentStep = 1);
                      }),
                    ],
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 10, crossAxisSpacing: 10),
                    itemCount: currentStep == 1 ? maxChapters : maxVerses,
                    itemBuilder: (context, i) => InkWell(
                      onTap: () async {
                        if (currentStep == 1) {
                          tempChapter = i + 1;
                          maxVerses = await _getMax('verse', tempBookId, tempChapter);
                          setST(() => currentStep = 2);
                        } else {
                          setState(() { _bookId = tempBookId; _chapter = tempChapter; });
                          _loadData(scrollToVerse: i + 1);
                          Navigator.pop(context);
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        alignment: Alignment.center,
                        child: Text("${i + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                      ),
                    ),
                  ),
            );
          },
        );
      },
      transitionBuilder: (context, a1, a2, child) => SlideTransition(position: Tween(begin: const Offset(0, -1), end: const Offset(0, 0)).animate(a1), child: child),
    );
  }

  Widget _gridKitab(List<Map<String, dynamic>> books, Function(int) onSelect) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 2.5, mainAxisSpacing: 8, crossAxisSpacing: 8),
      itemCount: books.length,
      itemBuilder: (context, i) => InkWell(
        onTap: () => onSelect(books[i]['book_number']),
        child: Container(
          decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Text(_shortenBookName(books[i]['long_name']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        title: GestureDetector(
          onTap: _showTopPicker,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("${_shortenBookName(_bookName)} $_chapter"),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          if (_selectedVerses.isNotEmpty)
            IconButton(icon: const Icon(Icons.copy), onPressed: () {
              String copyText = _selectedVerses.map((idx) => "${idx+1}. ${_cleanText(_verses[idx]['text'])}").join("\n");
              Clipboard.setData(ClipboardData(text: copyText));
              setState(() => _selectedVerses.clear());
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Disalin")));
            }),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _verses.length,
            itemBuilder: (context, i) {
              final v = _verses[i];
              final String? pTitle = _pericopes[v['verse']];
              bool isSelected = _selectedVerses.contains(i);

              return GestureDetector(
                onLongPress: () => setState(() => _selectedVerses.add(i)),
                onTap: () => setState(() => isSelected ? _selectedVerses.remove(i) : (_selectedVerses.isNotEmpty ? _selectedVerses.add(i) : null)),
                child: Container(
                  color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                  child: Column(
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
                              TextSpan(text: _cleanText(v['text'])),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }
}