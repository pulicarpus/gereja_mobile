import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'bible_models.dart';

class SearchPage extends StatefulWidget {
  final Database db;
  final List<BibleBook> allBooks;
  const SearchPage({super.key, required this.db, required this.allBooks});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  String _scope = "Semua"; // "Semua", "PL", "PB", "Kitab"
  int? _selectedBookNum;
  bool _isSearching = false;

  void _doSearch() async {
    if (_searchCtrl.text.isEmpty) return;
    setState(() => _isSearching = true);

    String query = "SELECT * FROM verses WHERE text LIKE ?";
    List<dynamic> args = ["%${_searchCtrl.text}%"];

    if (_scope == "PL") {
      query += " AND book_number < 400";
    } else if (_scope == "PB") {
      query += " AND book_number >= 400";
    } else if (_scope == "Kitab" && _selectedBookNum != null) {
      query += " AND book_number = ?";
      args.add(_selectedBookNum);
    }

    query += " LIMIT 100"; // Batasi agar tidak lag
    final data = await widget.db.rawQuery(query, args);

    setState(() {
      _results = data;
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Cari di Alkitab"), backgroundColor: Colors.indigo[900], foregroundColor: Colors.white),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: "Ketik kata kunci...",
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _doSearch),
                border: const OutlineInputBorder()
              ),
              onSubmitted: (_) => _doSearch(),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ["Semua", "PL", "PB", "Kitab"].map((s) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(s),
                  selected: _scope == s,
                  onSelected: (val) {
                    setState(() => _scope = s);
                    if (s == "Kitab") _showBookPicker();
                  },
                ),
              )).toList(),
            ),
          ),
          if (_isSearching) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final r = _results[i];
                final bName = widget.allBooks.firstWhere((b) => b.bookNumber == r['book_number']).name;
                return ListTile(
                  title: Text("$bName ${r['chapter']}:${r['verse']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(r['text'].toString().replaceAll(RegExp(r'<[^>]*>'), '')),
                  onTap: () => Navigator.pop(context, r),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  void _showBookPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: widget.allBooks.length,
        itemBuilder: (context, i) => ListTile(
          title: Text(widget.allBooks[i].name),
          onTap: () {
            setState(() => _selectedBookNum = widget.allBooks[i].bookNumber);
            Navigator.pop(context);
            _doSearch();
          },
        ),
      ),
    );
  }
}