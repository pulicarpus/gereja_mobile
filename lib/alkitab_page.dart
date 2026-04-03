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
  
  // Fitur Catatan & Seleksi
  Set<int> _selectedVerses = {}; 
  Map<int, String> _userNotes = {}; // key: verse_number, value: content

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

  Future<void> _initDatabase() async {
    var dbPath = await getDatabasesPath();
    var path = p.join(dbPath, "TB.SQLite3"); // Sesuaikan nama file
    _db = await openDatabase(path);
    
    // Buat tabel catatan jika belum ada
    await _db!.execute('CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, book_id INTEGER, chapter INTEGER, verse INTEGER, content TEXT, date TEXT)');
    
    await _loadBooks();
    await _loadData();
  }

  Future<void> _loadBooks() async {
    final books = await _db!.query('books', orderBy: 'book_number ASC');
    setState(() => _allBooks = books);
  }

  Future<void> _loadData({int? scrollToVerse}) async {
    setState(() => _isLoading = true);
    final verses = await _db!.query('verses', where: 'book_number = ? AND chapter = ?', whereArgs: [_bookId, _chapter]);
    
    // Load Catatan untuk pasal ini
    final notesData = await _db!.query('notes', where: 'book_id = ? AND chapter = ?', whereArgs: [_bookId, _chapter]);
    Map<int, String> tempNotes = {};
    for (var n in notesData) { tempNotes[n['verse'] as int] = n['content'] as String; }

    setState(() {
      _verses = verses;
      _userNotes = tempNotes;
      _bookName = _allBooks.firstWhere((b) => b['book_number'] == _bookId)['long_name'];
      _isLoading = false;
      _selectedVerses.clear();
    });

    if (scrollToVerse != null) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _scrollController.animateTo((scrollToVerse - 1) * 90.0, duration: const Duration(seconds: 1), curve: Curves.easeOut);
      });
    }
  }

  // --- FITUR PENCARIAN ---
  void _showSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setST) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: "Cari kata (mis: Kasih)...",
                  suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => setST(() {})),
                ),
                onSubmitted: (_) => setST(() {}),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _searchBible(_searchController.text),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || _searchController.text.isEmpty) return const Center(child: Text("Masukkan kata kunci"));
                    return ListView.builder(
                      itemCount: snapshot.data!.length,
                      itemBuilder: (context, i) {
                        var res = snapshot.data![i];
                        return ListTile(
                          title: Text("${res['long_name']} ${res['chapter']}:${res['verse']}"),
                          subtitle: Text(res['text'], maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            Navigator.pop(context);
                            setState(() {
                              _bookId = res['book_number'];
                              _chapter = res['chapter'];
                            });
                            _loadData(scrollToVerse: res['verse']);
                          },
                        );
                      },
                    );
                  },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _searchBible(String query) async {
    if (query.length < 3) return [];
    return await _db!.rawQuery('SELECT v.*, b.long_name FROM verses v JOIN books b ON v.book_number = b.book_number WHERE v.text LIKE ? LIMIT 50', ['%$query%']);
  }

  // --- FITUR CATATAN ---
  void _addNote(int verseNum) {
    TextEditingController _noteEdit = TextEditingController(text: _userNotes[verseNum] ?? "");
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Catatan Ayat $verseNum"),
        content: TextField(controller: _noteEdit, maxLines: 3, decoration: const InputDecoration(hintText: "Tulis catatan...")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () async {
              String date = DateFormat('dd MMM yyyy').format(DateTime.now());
              await _db!.insert('notes', {
                'book_id': _bookId,
                'chapter': _chapter,
                'verse': verseNum,
                'content': _noteEdit.text,
                'date': date
              }, conflictAlgorithm: ConflictAlgorithm.replace);
              Navigator.pop(context);
              _loadData();
            },
            child: const Text("Simpan"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("$_bookName $_chapter"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _showSearch),
          if (_selectedVerses.isNotEmpty) ...[
            IconButton(icon: const Icon(Icons.copy), onPressed: () {
              String copyText = _selectedVerses.map((idx) => "${idx+1}. ${_verses[idx]['text']}").join("\n");
              Clipboard.setData(ClipboardData(text: copyText));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ayat disalin")));
              setState(() => _selectedVerses.clear());
            }),
            IconButton(icon: const Icon(Icons.edit_note), onPressed: () => _addNote(_selectedVerses.first + 1)),
          ]
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _verses.length,
            itemBuilder: (context, i) {
              bool isSelected = _selectedVerses.contains(i);
              bool hasNote = _userNotes.containsKey(i + 1);
              return GestureDetector(
                onLongPress: () => setState(() => _selectedVerses.add(i)),
                onTap: () {
                  if (_selectedVerses.isNotEmpty) {
                    setState(() => isSelected ? _selectedVerses.remove(i) : _selectedVerses.add(i));
                  } else if (hasNote) {
                    _addNote(i + 1);
                  }
                },
                child: Container(
                  color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.5),
                          children: [
                            TextSpan(text: "${i + 1} ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 14)),
                            TextSpan(text: _verses[i]['text']),
                            if (hasNote) const TextSpan(text: "  📝", style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                      if (hasNote)
                        Padding(
                          padding: const EdgeInsets.only(left: 20, top: 4),
                          child: Text(_userNotes[i+1]!, style: const TextStyle(color: Colors.brown, fontStyle: FontStyle.italic, fontSize: 14)),
                        )
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }
}