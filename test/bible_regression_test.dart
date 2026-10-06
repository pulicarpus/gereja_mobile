import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:gereja_mobile/bible_local_store.dart';
import 'package:gereja_mobile/bible_models.dart';
import 'package:gereja_mobile/bible_support.dart';
import 'package:gereja_mobile/ayat_data.dart';
import 'package:gereja_mobile/search_page.dart';

class QueryDatabase implements Database {
  Future<List<Map<String, Object?>>> Function() handler;
  QueryDatabase(this.handler);
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
  }) => handler();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final books = [
    BibleBook(bookNumber: 400, name: 'Mikha', shortName: 'Mi'),
    BibleBook(bookNumber: 470, name: 'Matius', shortName: 'Mat'),
    BibleBook(bookNumber: 500, name: 'Yohanes', shortName: 'Yoh'),
    BibleBook(bookNumber: 700, name: '\n2 Yohanes', shortName: '2Yoh'),
  ];

  test('Semua kitab PL/PB, audio dan batas pasal memakai ID yang sama', () {
    expect(bibleBookIds.length, 66);
    expect(bibleBookIds.toSet().length, 66);
    expect(isOldTestament(400), isTrue);
    expect(isOldTestament(460), isTrue);
    expect(isOldTestament(470), isFalse);
    expect(bibleAudioPath(bibleOrdinal(480)!, 1), 'markus/02_mrk01.mp3');
    expect(
      bibleAudioPath(bibleOrdinal(110)!, 22),
      '1raja-raja/11_1Kings_22.mp3',
    );
    expect(bibleAudioPath(bibleOrdinal(230)!, 150), 'mazmur/19_mzm150.mp3');
    expect(() => bibleAudioPath(50, 5), throwsArgumentError);
  });

  test(
    'Referensi multi rentang dan nama berbaris baru tidak kehilangan ayat',
    () {
      final reference = BibleReference.parse('Yohanes 3:1-3, 5, 7-8', books)!;
      expect(reference.verses, [1, 2, 3, 5, 7, 8]);
      expect(BibleReference.parse('2 Yohanes 1:4', books)!.bookId, 700);
      expect(BibleReference.parse('Yohanes 3:5-2', books), isNull);
      expect(BibleReference.parse('Yohanes 3:0', books), isNull);
      expect(BibleReference.parse('Yohanes 3:1,', books), isNull);
    },
  );

  test(
    'Teks salin dan pencarian bebas simbol catatan kaki; puisi tetap terbaca',
    () {
      expect(
        cleanBibleText('<pb/><f>ⓐ </f>Yesus <J>berkata</J>'),
        'Yesus berkata',
      );
      expect(
        cleanBibleText('<t>baris satu</t> <t>baris dua</t>'),
        'baris satu\nbaris dua',
      );
      expect(
        cleanBibleText('kepadanya: <J>“Biarlah</J>'),
        'kepadanya: “Biarlah',
      );
    },
  );

  test('Catatan lama, JSON lokal, dan raw_data backup mempertahankan isi', () {
    final old = NoteModel.fromRaw(
      'Note_1',
      'Yohanes 3:16~|~Judul~|~Pendeta~|~Tanggal~|~ ~|~awal~|~akhir',
    );
    expect(old.content, 'awal~|~akhir');
    final local = NoteModel.fromRaw(old.key, old.toLocalJson());
    expect(local.content, old.content);
    expect(local.toLegacyRaw(), old.toLegacyRaw());
    expect(local.preacher, 'Pendeta');
  });

  test(
    'Catatan, stabilo, penghapusan dan impor dipisahkan antar akun',
    () async {
      SharedPreferences.setMockInitialValues({
        'ALL_NOTE_KEYS': ['Note_lama'],
        'Note_lama': 'Yohanes 3:16~|~Lama~|~P~|~D~|~ ~|~Isi',
        'BIBLE_HIGHLIGHTS': '{rusak',
      });
      final prefs = await SharedPreferences.getInstance();
      final a = BibleLocalStore(prefs, 'akun-a');
      final b = BibleLocalStore(prefs, 'akun-b');
      final guest = BibleLocalStore(prefs, null);
      expect(a.noteKeys, isEmpty);
      expect(b.noteKeys, isEmpty);
      expect(await a.importLegacyNotes(), 1);
      expect(b.noteKeys, isEmpty);
      expect(guest.noteKeys, isEmpty);
      expect(prefs.getString('Note_lama'), isNotNull);
      await a.saveHighlights({
        '500_3_16': {'color': 123, 'label': 'Kasih'},
      });
      expect(b.loadHighlights(), isEmpty);
      await a.deleteNote('Note_lama');
      expect(a.deletedKeys, contains('Note_lama'));
      expect(await a.importLegacyNotes(), 0);
      expect(await b.importLegacyNotes(), 1);
      expect(b.readNote('Note_lama'), isNotNull);
    },
  );

  test('Ayat harian tetap sepanjang tanggal termasuk pembukaan ulang', () {
    expect(
      AyatData.getAyatHariIni(DateTime(2026, 10, 6, 0)),
      AyatData.getAyatHariIni(DateTime(2026, 10, 6, 23, 59)),
    );
    expect(
      AyatData.getAyatHariIni(DateTime(2026, 10, 7)),
      isNot(AyatData.getAyatHariIni(DateTime(2026, 10, 6))),
    );
    expect(AyatData.daftarAyat.every((v) => v['isi']!.isNotEmpty), isTrue);
  });

  final rows = <Map<String, Object?>>[
    {'book_number': 400, 'chapter': 1, 'verse': 1, 'text': 'Kasih'},
    {
      'book_number': 470,
      'chapter': 3,
      'verse': 15,
      'text': 'kepadanya: <J>“Biarlah</J> kasih',
    },
  ];
  testWidgets('PB tidak memasukkan Mikha; frasa lintas tag dapat ditemukan', (
    tester,
  ) async {
    final db = QueryDatabase(() async => rows);
    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(db: db, allBooks: books, currentBookNum: 470),
      ),
    );
    await tester.enterText(find.byType(TextField), 'kasih');
    await tester.tap(find.text('PB'));
    await tester.pumpAndSettle();
    expect(find.text('Mikha 1:1'), findsNothing);
    expect(find.text('Matius 3:15'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'kepadanya: “Biarlah');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.text('Matius 3:15'), findsOneWidget);
  });

  testWidgets('Query gagal menutup loading dan dapat dicoba kembali', (
    tester,
  ) async {
    var fail = true;
    final db = QueryDatabase(() async {
      if (fail) throw StateError('Database terputus');
      return rows;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(db: db, allBooks: books, currentBookNum: 470),
      ),
    );
    await tester.enterText(find.byType(TextField), 'kasih');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Pencarian gagal. Silakan coba lagi.'), findsOneWidget);
    fail = false;
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.text('Matius 3:15'), findsOneWidget);
  });

  testWidgets(
    'Request lama tidak menimpa filter baru; aman setelah halaman ditutup',
    (tester) async {
      final first = Completer<List<Map<String, Object?>>>();
      final second = Completer<List<Map<String, Object?>>>();
      var calls = 0;
      final db = QueryDatabase(
        () => ++calls == 1 ? first.future : second.future,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SearchPage(db: db, allBooks: books, currentBookNum: 470),
        ),
      );
      await tester.enterText(find.byType(TextField), 'kasih');
      await tester.tap(find.byIcon(Icons.search));
      await tester.tap(find.text('PB'));
      second.complete(rows);
      await tester.pumpAndSettle();
      first.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('Matius 3:15'), findsOneWidget);
      final pending = Completer<List<Map<String, Object?>>>();
      db.handler = () => pending.future;
      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      pending.complete(rows);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
