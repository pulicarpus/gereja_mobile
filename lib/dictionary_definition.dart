import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:sqflite/sqflite.dart';
import 'bible_models.dart';
import 'bible_support.dart';
import 'dictionary_store.dart';

class DictionaryDefinition extends StatefulWidget {
  final DictionaryEntry entry;
  final List<BibleBook> books;
  final void Function(String, BibleReference)? onReference;
  const DictionaryDefinition({
    super.key,
    required this.entry,
    required this.books,
    this.onReference,
  });
  @override
  State<DictionaryDefinition> createState() => _DictionaryDefinitionState();
}

class _DictionaryDefinitionState extends State<DictionaryDefinition> {
  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan> _spans = [];
  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(DictionaryDefinition old) {
    super.didUpdateWidget(old);
    _prepare();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _prepare() {
    _clear();
    final aliases = <String, BibleBook>{};
    for (final book in widget.books) {
      for (final alias in [
        book.name,
        book.shortName,
        book.shortName.replaceAll(' ', ''),
      ]) {
        aliases[alias.toLowerCase()] = book;
      }
    }
    for (final alias in {
      'Mazm': 'Mazmur',
      '1Tim': '1 Timotius',
      '2Tim': '2 Timotius',
      '1Pet': '1 Petrus',
      '2Pet': '2 Petrus',
    }.entries) {
      for (final book in widget.books) {
        if (book.name == alias.value) aliases[alias.key.toLowerCase()] = book;
      }
    }
    final names = aliases.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final pattern = names.isEmpty
        ? null
        : RegExp(
            '(?:(${names.map(RegExp.escape).join('|')})\\s+)?(\\d+):(\\d+(?:\\s*[-,]\\s*\\d+)*)',
            caseSensitive: false,
          );
    final verified = widget.entry.references.toSet();
    _spans = [];
    final paragraphs = widget.entry.definition.split('\n\n');
    for (var index = 0; index < paragraphs.length; index++) {
      final text = paragraphs[index];
      if (widget.entry.headings.contains(text)) {
        _spans.add(
          TextSpan(
            text: text,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      } else if (pattern == null || widget.onReference == null) {
        _spans.add(TextSpan(text: text));
      } else {
        BibleBook? current;
        var offset = 0;
        for (final match in pattern.allMatches(text)) {
          _spans.add(TextSpan(text: text.substring(offset, match.start)));
          if (match[1] != null) current = aliases[match[1]!.toLowerCase()];
          final label = current == null
              ? null
              : '${current.name} ${match[2]}:${match[3]!.replaceAll(RegExp(r'\s+'), '')}';
          final ref = label == null || !verified.contains(label)
              ? null
              : BibleReference.parse(label, widget.books);
          final visible = match.group(0)!;
          if (ref == null) {
            _spans.add(TextSpan(text: visible));
          } else {
            final recognizer = TapGestureRecognizer()
              ..onTap = () => widget.onReference?.call(label!, ref);
            _recognizers.add(recognizer);
            _spans.add(
              TextSpan(
                text: visible,
                recognizer: recognizer,
                style: const TextStyle(
                  color: Colors.indigo,
                  decoration: TextDecoration.underline,
                ),
              ),
            );
          }
          offset = match.end;
        }
        _spans.add(TextSpan(text: text.substring(offset)));
      }
      if (index != paragraphs.length - 1)
        _spans.add(const TextSpan(text: '\n\n'));
    }
  }

  @override
  Widget build(BuildContext context) => SelectableText.rich(
    TextSpan(children: _spans),
    style: const TextStyle(fontSize: 17, height: 1.6),
  );
}

class DictionaryVerseDialog extends StatefulWidget {
  final Database db;
  final String label;
  final BibleReference reference;
  const DictionaryVerseDialog({
    super.key,
    required this.db,
    required this.label,
    required this.reference,
  });
  @override
  State<DictionaryVerseDialog> createState() => _DictionaryVerseDialogState();
}

class _DictionaryVerseDialogState extends State<DictionaryVerseDialog> {
  late final Future<List<Map<String, Object?>>> _verses = widget.db.query(
    'verses',
    where:
        'book_number = ? AND chapter = ? AND verse IN (${List.filled(widget.reference.verses.length, '?').join(',')})',
    whereArgs: [
      widget.reference.bookId,
      widget.reference.chapter,
      ...widget.reference.verses,
    ],
    orderBy: 'verse',
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.label),
    content: SizedBox(
      width: 600,
      child: FutureBuilder<List<Map<String, Object?>>>(
        future: _verses,
        builder: (_, snapshot) {
          if (snapshot.hasError)
            return const Text('Ayat belum dapat dimuat. Tutup dan coba lagi.');
          if (!snapshot.hasData)
            return const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            );
          final rows = snapshot.data!;
          if (rows.isEmpty)
            return const Text('Ayat tidak tersedia pada versi Alkitab ini.');
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows
                  .map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SelectableText(
                        '${row['verse']}. ${cleanBibleText(row['text'].toString())}',
                        style: const TextStyle(fontSize: 17, height: 1.5),
                      ),
                    ),
                  )
                  .toList(),
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Tutup'),
      ),
    ],
  );
}
