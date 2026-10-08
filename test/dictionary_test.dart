import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/bible_models.dart';
import '../lib/dictionary_store.dart';
import '../lib/kamus_page.dart';
import '../lib/dictionary_definition.dart';
import 'package:flutter/gestures.dart';

void main() {
  late Database db;
  late DictionaryStore store;
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE entries (id INTEGER PRIMARY KEY, term TEXT, search_term TEXT, definition TEXT, source TEXT, refs TEXT)',
    );
    final entries =
        jsonDecode(await File('assets/dictionary/sample.json').readAsString())
            as List;
    for (final entry in entries) {
      await db.insert('entries', {
        'term': entry['term'],
        'search_term': (entry['term'] as String).toLowerCase(),
        'definition': entry['definition'],
        'source': entry['source'],
        'refs': jsonEncode(entry['references']),
      });
    }
    await db.execute(
      'CREATE TABLE verses(book_number INTEGER, chapter INTEGER, verse INTEGER, text TEXT)',
    );
    for (final verse in [37, 38, 39]) {
      await db.insert('verses', {
        'book_number': 470,
        'chapter': 22,
        'verse': verse,
        'text': '<t>Isi ayat $verse</t>',
      });
    }
    store = DictionaryStore(db);
  });
  tearDown(() => db.close());
  test(
    'Offline SQLite searches exact, prefix and mixed case; wildcards are literal',
    () async {
      expect((await store.search('  kAsIh ')).single.term, 'Kasih');
      expect((await store.search('ma')).single.term, 'Manna');
      expect(await store.search('%'), isEmpty);
      expect(await store.search('_'), isEmpty);
      expect(await store.search('not-in-dictionary'), isEmpty);
      expect(await store.search(''), hasLength(3));
    },
  );
  test(
    'Packaged SABDA database contains complete searchable definitions',
    () async {
      final packaged = await databaseFactoryFfi.openDatabase(
        File('assets/dictionary/offline.sqlite').absolute.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        final dictionary = DictionaryStore(packaged);
        final count = await packaged.rawQuery(
          'SELECT COUNT(*) AS n FROM entries',
        );
        expect(count.single['n'], 18386);
        for (final term in ['Kasih', 'Manna', 'Abraham', 'Iman']) {
          final entries = await dictionary.search(term);
          expect(entries, isNotEmpty);
          expect(entries.first.definition.length, greaterThan(100));
          expect(entries.first.source, contains('SABDA'));
          expect(entries.first.references, isNotEmpty);
        }
        expect((await dictionary.search('Kasih')).first.term, 'Kasih');
        expect(await dictionary.search('%'), isEmpty);
      } finally {
        await packaged.close();
      }
    },
  );
  testWidgets(
    'Inline references include inherited chapters and headings are bold',
    (tester) async {
      final books = [
        BibleBook(bookNumber: 470, name: 'Matius', shortName: 'Mat'),
      ];
      final clicked = <String>[];
      final entry = DictionaryEntry(
        term: 'Kasih',
        definition: 'Kasih [kamus browning]\n\nMat 22:37; 22:39; 99:1',
        source: 'SABDA',
        references: ['Matius 22:37', 'Matius 22:39'],
        headings: ['Kasih [kamus browning]'],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DictionaryDefinition(
              entry: entry,
              books: books,
              onReference: (label, ref) => clicked.add(label),
            ),
          ),
        ),
      );
      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      final spans = text.textSpan!.children!.cast<TextSpan>();
      expect(spans.first.style!.fontWeight, FontWeight.bold);
      final links = spans.where((span) => span.recognizer != null).toList();
      expect(links.map((span) => span.text), ['Mat 22:37', '22:39']);
      for (final link in links) {
        (link.recognizer as TapGestureRecognizer).onTap!();
      }
      expect(clicked, ['Matius 22:37', 'Matius 22:39']);
    },
  );
  testWidgets(
    'Search opens sourced definition and verse popup without leaving dictionary',
    (tester) async {
      final books = [
        BibleBook(bookNumber: 470, name: 'Matius', shortName: 'Mat'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => KamusPage(store: store, allBooks: books, bibleDb: db),
                    ),
                  );
                },
                child: const Text('Buka kamus'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Buka kamus'));
      await tester.pump();
      await tester.runAsync(() => store.search(''));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'kas');
      await tester.runAsync(() => store.search('kas'));
      await tester.pumpAndSettle();
      expect(find.text('Kasih'), findsOneWidget);
      expect(find.text('Manna'), findsNothing);
      await tester.tap(find.text('Kasih'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Sumber: Data contoh GKII Mobile'),
        findsOneWidget,
      );
      await tester.tap(find.text('Matius 22:37-39'));
      await tester.pump();
      await tester.runAsync(() => db.rawQuery('SELECT * FROM verses'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('37. Isi ayat 37'), findsOneWidget);
      expect(find.text('39. Isi ayat 39'), findsOneWidget);
      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(DictionaryDetailPage), findsOneWidget);
    },
  );
}
