import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../lib/bible_models.dart';
import '../lib/sermon_page.dart';

class SermonDatabase implements Database {
  List<Object?>? lastArguments;
  bool fail = false;
  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    lastArguments = whereArgs;
    if (fail) throw StateError('Database unavailable');
    return [
      for (final verse in [1, 2, 3, 5])
        {'verse': verse, 'text': '<t>Isi ayat $verse</t>'},
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final books = [BibleBook(bookNumber: 470, name: 'Matius', shortName: 'Mat')];
  NoteModel note() => NoteModel(
    key: 'sermon',
    nas: 'Mat 5:1',
    title: 'Ketenangan',
    date: '',
    content: '',
    rawData: '',
    richDelta: [
      {'insert': 'Pendahuluan'},
      {
        'insert': '\n',
        'attributes': {'header': 1},
      },
      {
        'insert': 'Baca Mat',
        'attributes': {'bold': true},
      },
      {'insert': '. 5:1-3,5 dan Matius 5:1.'},
      {'insert': '\n'},
      {
        'insert': List.generate(
          30,
          (i) => 'Penjelasan bagian ${i + 1}.\n',
        ).join(),
      },
      {'insert': 'Penutup'},
      {
        'insert': '\n',
        'attributes': {'header': 2},
      },
      {'insert': 'Akhir khotbah.\n'},
    ],
  );
  Future<void> tapReference(WidgetTester tester, String fragment) async {
    final finder = find.textContaining('Baca Mat', findRichText: true).first;
    final rich = tester.widget<RichText>(finder);
    final text = rich.text.toPlainText();
    final index = text.indexOf(fragment);
    expect(index, greaterThanOrEqualTo(0));
    final render = tester.renderObject<RenderParagraph>(finder);
    final box = render
        .getBoxesForSelection(
          TextSelection(baseOffset: index, extentOffset: index + 3),
        )
        .first;
    await tester.tapAt(render.localToGlobal(box.toRect().center));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Actual inline abbreviation and full name open offline verses without losing position',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = SermonDatabase();
      await tester.pumpWidget(
        MaterialApp(
          home: SermonPage(
            note: note(),
            db: db,
            books: books,
            prefs: prefs,
            ownerUid: 'reader',
            manageDevice: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('sermon-scroll')),
          )
          .controller!;
      final initial = scroll.offset;
      await tapReference(tester, 'Mat.');
      expect(db.lastArguments, [470, 5]);
      expect(find.text('Matius 5:1-3,5'), findsOneWidget);
      expect(find.text('1. Isi ayat 1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(scroll.offset, initial);
      await tester.tap(find.byTooltip('Tutup ayat'));
      await tester.pumpAndSettle();
      expect(scroll.offset, initial);
      await tapReference(tester, 'Matius');
      expect(find.text('Matius 5:1'), findsOneWidget);
      await tester.tap(find.byTooltip('Tutup ayat'));
      await tester.pumpAndSettle();
      expect(scroll.offset, initial);
      // Unavailable databases produce an inline error instead of losing the note.
      db.fail = true;
      await tapReference(tester, 'Mat.');
      expect(find.textContaining('Ayat belum dapat dimuat.'), findsOneWidget);
      await tester.tap(find.byTooltip('Tutup ayat'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Auto scroll pauses for scripture, manual scrolling stops it and sections/settings work',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SermonPage(
            note: note(),
            db: SermonDatabase(),
            books: books,
            manageDevice: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('sermon-scroll')),
          )
          .controller!;
      await tester.tap(find.byTooltip('Mulai gulir otomatis'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(scroll.offset, greaterThan(0));
      await tapReference(tester, 'Mat.');
      final paused = scroll.offset;
      await tester.pump(const Duration(seconds: 2));
      expect(scroll.offset, paused);
      await tester.tap(find.byTooltip('Tutup ayat'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byTooltip('Jeda gulir otomatis'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('sermon-scroll')),
        const Offset(0, -50),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Mulai gulir otomatis'), findsOneWidget);
      await tester.tap(find.byTooltip('Pengaturan khotbah'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gelap'));
      await tester.drag(
        find.byKey(const ValueKey('sermon-font-slider')),
        const Offset(30, 0),
      );
      await tester.tap(find.text('Selesai'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bagian khotbah'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Penutup').last);
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(100));
      await tester.tap(find.byTooltip('Sembunyikan kontrol'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      await tester.tap(find.byTooltip('Tampilkan kontrol'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sermon-elapsed')));
      await tester.pumpAndSettle();
      expect(find.text('Timer khotbah'), findsOneWidget);
      await tester.tap(find.text('Jeda timer'));
      await tester.pumpAndSettle();
      final elapsed = tester
          .widget<Text>(find.byKey(const ValueKey('sermon-elapsed')))
          .data;
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('sermon-elapsed'))).data,
        elapsed,
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(tester.takeException(), isNull);
    },
  );
}
