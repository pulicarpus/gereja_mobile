import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'dictionary_definition.dart';
import 'bible_models.dart';
import 'bible_support.dart';
import 'dictionary_store.dart';
import 'kamus_ai_page.dart';

class KamusPage extends StatefulWidget {
  final String? kataBawaan;
  final List<BibleBook> allBooks;
  final DictionaryStore? store;
  final Database? bibleDb;
  const KamusPage({
    super.key,
    this.kataBawaan,
    this.allBooks = const [],
    this.store,
    this.bibleDb,
  });
  @override
  State<KamusPage> createState() => _KamusPageState();
}

class _KamusPageState extends State<KamusPage> {
  late final TextEditingController _search = TextEditingController(
    text: widget.kataBawaan ?? '',
  );
  List<DictionaryEntry> _entries = [];
  bool _loading = true;
  String? _error;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _find(_search.text);
  }

  @override
  void dispose() {
    _request++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _find(String text) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = widget.store ?? await DictionaryStore.open();
      final entries = await store.search(text);
      if (!mounted || request != _request) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = 'Kamus belum dapat dibuka. Silakan coba lagi.';
      });
    }
  }

  Future<void> _show(DictionaryEntry entry) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DictionaryDetailPage(
          entry: entry,
          allBooks: widget.allBooks,
          bibleDb: widget.bibleDb,
        ),
      ),
    );
    if (mounted && result is Map<String, int>) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Kamus Alkitab'),
      actions: [
        IconButton(
          tooltip: 'Cari dengan AI (internet)',
          icon: const Icon(Icons.auto_awesome),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => KamusAiPage(kataBawaan: _search.text),
            ),
          ),
        ),
      ],
    ),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Kamus offline · SABDA\nKetik istilah untuk mencari definisi.',
            textAlign: TextAlign.center,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _search,
            onChanged: _find,
            onSubmitted: _find,
            decoration: const InputDecoration(
              labelText: 'Cari istilah',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(
                        onPressed: () => _find(_search.text),
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                )
              : _entries.isEmpty
              ? const Center(
                  child: Text('Istilah belum tersedia di kamus offline.'),
                )
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (_, index) {
                    final entry = _entries[index];
                    return ListTile(
                      title: Text(entry.term),
                      subtitle: Text(
                        entry.definition,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _show(entry),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class DictionaryDetailPage extends StatelessWidget {
  final DictionaryEntry entry;
  final List<BibleBook> allBooks;
  final Database? bibleDb;
  const DictionaryDetailPage({
    super.key,
    required this.entry,
    this.allBooks = const [],
    this.bibleDb,
  });

  Future<void> _showVerse(
    BuildContext context,
    String label,
    BibleReference ref,
  ) async {
    final db = bibleDb;
    if (db == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) =>
          DictionaryVerseDialog(db: db, label: label, reference: ref),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(entry.term)),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DictionaryDefinition(
            entry: entry,
            books: allBooks,
            onReference: bibleDb == null
                ? null
                : (label, ref) => _showVerse(context, label, ref),
          ),
          const SizedBox(height: 20),
          Text(
            'Sumber: ${entry.source}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (entry.references.isNotEmpty) ...[
            const Divider(height: 32),
            const Text(
              'Referensi ayat',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ...entry.references.map((text) {
              final ref = BibleReference.parse(text, allBooks);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(text),
                trailing: ref == null ? null : const Icon(Icons.open_in_new),
                onTap: ref == null || bibleDb == null
                    ? null
                    : () => _showVerse(context, text, ref),
              );
            }),
          ],
        ],
      ),
    ),
  );
}
