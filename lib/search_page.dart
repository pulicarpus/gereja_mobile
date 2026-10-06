import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'bible_models.dart';
import 'bible_support.dart';

class SearchPage extends StatefulWidget {
  final Database db;
  final List<BibleBook> allBooks;
  final int currentBookNum;

  const SearchPage({
    super.key,
    required this.db,
    required this.allBooks,
    required this.currentBookNum,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  String _scope = "Semua";
  bool _isSearching = false;
  bool _hasSearched = false;
  int _request = 0;
  String _resultQuery = '';
  String? _error;
  int _visibleCount = 100;

  @override
  void dispose() {
    _request++;
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _currentBookName {
    try {
      return widget.allBooks
          .firstWhere((b) => b.bookNumber == widget.currentBookNum)
          .name;
    } catch (e) {
      return "Kitab Ini";
    }
  }

  Future<void> _doSearch() async {
    final keyword = _searchCtrl.text.trim();
    if (keyword.isEmpty) return;
    final request = ++_request;
    final scope = _scope;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _error = null;
    });
    try {
      // Normalisasi sebelum pencocokan: frasa tidak terputus tag format.
      final data = await widget.db.query(
        'verses',
        orderBy: 'book_number, chapter, verse',
      );
      if (!mounted || request != _request) return;
      final lower = keyword.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      final reference = BibleReference.parse(keyword, widget.allBooks);
      final results = data.where((row) {
        final bookId = row['book_number'] as int;
        if (scope == 'PL' && !isOldTestament(bookId)) return false;
        if (scope == 'PB' && isOldTestament(bookId)) return false;
        if (scope == _currentBookName && bookId != widget.currentBookNum)
          return false;
        if (reference != null) {
          return bookId == reference.bookId &&
              row['chapter'] == reference.chapter &&
              reference.verses.contains(row['verse']);
        }
        return cleanBibleText(row['text'].toString())
            .replaceAll(RegExp(r'\s+'), ' ')
            .toLowerCase()
            .contains(lower);
      }).toList();
      setState(() {
        _results = results;
        _resultQuery = reference == null ? keyword : '';
        _visibleCount = 100;
      });
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _results = [];
          _error = 'Pencarian gagal. Silakan coba lagi.';
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => _isSearching = false);
    }
  }

  // =====================================================================
  // FUNGSI BARU: Memberikan efek Stabilo Kuning pada kata kunci
  // =====================================================================
  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return Text(
        text,
        style: const TextStyle(fontSize: 16, color: Colors.black87),
      );
    }

    String lowerText = text.toLowerCase();
    String lowerQuery = query.toLowerCase();
    if (lowerText.length != text.length || lowerQuery.length != query.length) {
      return Text(text);
    }
    List<TextSpan> spans = [];
    int start = 0;
    int indexOfMatch;

    // Mencari semua kecocokan kata kunci di dalam teks ayat
    while ((indexOfMatch = lowerText.indexOf(lowerQuery, start)) != -1) {
      // Masukkan teks normal (sebelum kata kunci)
      if (indexOfMatch > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, indexOfMatch),
            style: const TextStyle(color: Colors.black87),
          ),
        );
      }
      // Masukkan teks kata kunci (diberi efek stabilo kuning & cetak tebal)
      spans.add(
        TextSpan(
          text: text.substring(indexOfMatch, indexOfMatch + query.length),
          style: const TextStyle(
            backgroundColor: Colors.yellow,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      start = indexOfMatch + query.length;
    }

    // Masukkan sisa teks normal setelah kata kunci terakhir
    if (start < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(start),
          style: const TextStyle(color: Colors.black87),
        ),
      );
    }

    return RichText(
      text: TextSpan(style: const TextStyle(fontSize: 16), children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cari di Alkitab"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: "Ketik kata kunci...",
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _doSearch,
                ),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onSubmitted: (_) => _doSearch(),
            ),
          ),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ["Semua", "PL", "PB", _currentBookName]
                  .map(
                    (s) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(
                          s,
                          style: TextStyle(
                            color: _scope == s ? Colors.white : Colors.black87,
                          ),
                        ),
                        selectedColor: Colors.indigo[600],
                        selected: _scope == s,
                        onSelected: (val) {
                          setState(() => _scope = s);
                          if (_searchCtrl.text.isNotEmpty) _doSearch();
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),

          if (_isSearching) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),

          if (!_isSearching && _hasSearched)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                "Ditemukan ${_results.length} hasil",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo[900],
                  fontSize: 15,
                ),
              ),
            ),

          const Divider(height: 1),

          Expanded(
            child: _results.isEmpty && _hasSearched && !_isSearching
                ? const Center(child: Text("Kata kunci tidak ditemukan."))
                : ListView.builder(
                    itemCount: _results.length > _visibleCount
                        ? _visibleCount + 1
                        : _results.length,
                    itemBuilder: (context, i) {
                      if (i == _visibleCount) {
                        return TextButton(
                          onPressed: () => setState(() => _visibleCount += 100),
                          child: const Text('Tampilkan hasil berikutnya'),
                        );
                      }
                      final r = _results[i];
                      final bName = widget.allBooks
                          .firstWhere((b) => b.bookNumber == r['book_number'])
                          .name;

                      // Bersihkan tag HTML terlebih dahulu
                      final cleanedText = cleanBibleText(r['text'].toString());

                      return ListTile(
                        title: Text(
                          "$bName ${r['chapter']}:${r['verse']}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        // Panggil fungsi Highlight di sini
                        subtitle: _buildHighlightedText(
                          cleanedText,
                          _resultQuery,
                        ),
                        // Saat diklik, lempar data kembali ke AlkitabPage untuk di-scroll
                        onTap: _isSearching
                            ? null
                            : () => Navigator.pop(context, r),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
