import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'bible_models.dart';

class SearchPage extends StatefulWidget {
  final Database db;
  final List<BibleBook> allBooks;
  final int currentBookNum; // Tambahan: Menerima kitab yang sedang dibuka

  const SearchPage({
    super.key, 
    required this.db, 
    required this.allBooks,
    required this.currentBookNum, // Wajib diisi dari alkitab_page
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  String _scope = "Semua"; 
  bool _isSearching = false;
  bool _hasSearched = false; // Penanda apakah user sudah pernah menekan tombol cari

  // Fungsi untuk mengambil nama kitab yang sedang dibuka saat ini
  String get _currentBookName {
    try {
      return widget.allBooks.firstWhere((b) => b.bookNumber == widget.currentBookNum).name;
    } catch (e) {
      return "Kitab Ini";
    }
  }

  void _doSearch() async {
    if (_searchCtrl.text.isEmpty) return;
    
    // Sembunyikan keyboard saat mencari (Bagus untuk pengalaman di Tablet)
    FocusScope.of(context).unfocus(); 
    
    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    String query = "SELECT * FROM verses WHERE text LIKE ?";
    List<dynamic> args = ["%${_searchCtrl.text}%"];

    // Logika filter scope
    if (_scope == "PL") {
      query += " AND book_number < 400";
    } else if (_scope == "PB") {
      query += " AND book_number >= 400";
    } else if (_scope == _currentBookName) { // Scope pencarian khusus kitab ini
      query += " AND book_number = ?";
      args.add(widget.currentBookNum);
    }

    // LIMIT DIHAPUS - Menampilkan semua hasil
    final data = await widget.db.rawQuery(query, args);

    setState(() {
      _results = data;
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cari di Alkitab"), 
        backgroundColor: Colors.indigo[900], 
        foregroundColor: Colors.white
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search, // Tombol enter di keyboard jadi 'Cari'
              decoration: InputDecoration(
                hintText: "Ketik kata kunci...",
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _doSearch),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onSubmitted: (_) => _doSearch(),
            ),
          ),
          
          // Chip Filter Scope
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              // "Kitab" diganti dengan nama kitab asli (misal: "Matius")
              children: ["Semua", "PL", "PB", _currentBookName].map((s) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(s, style: TextStyle(color: _scope == s ? Colors.white : Colors.black87)),
                  selectedColor: Colors.indigo[600],
                  selected: _scope == s,
                  onSelected: (val) {
                    setState(() => _scope = s);
                    // Langsung cari otomatis kalau text field tidak kosong
                    if (_searchCtrl.text.isNotEmpty) _doSearch(); 
                  },
                ),
              )).toList(),
            ),
          ),
          
          if (_isSearching) const LinearProgressIndicator(),
          
          // INDIKATOR JUMLAH PENCARIAN
          if (!_isSearching && _hasSearched)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                "Ditemukan ${_results.length} hasil",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo[900], fontSize: 15),
              ),
            ),
            
          const Divider(height: 1),
          
          Expanded(
            child: _results.isEmpty && _hasSearched && !_isSearching
              ? const Center(child: Text("Kata kunci tidak ditemukan."))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final r = _results[i];
                    final bName = widget.allBooks.firstWhere((b) => b.bookNumber == r['book_number']).name;
                    return ListTile(
                      title: Text(
                        "$bName ${r['chapter']}:${r['verse']}", 
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)
                      ),
                      // Membersihkan tag HTML (seperti <x> atau <i>) dari teks pencarian
                      subtitle: Text(
                        r['text'].toString().replaceAll(RegExp(r'<[^>]*>'), ''),
                        style: const TextStyle(fontSize: 16, color: Colors.black87),
                      ),
                      onTap: () => Navigator.pop(context, r),
                    );
                  },
                ),
          )
        ],
      ),
    );
  }
}