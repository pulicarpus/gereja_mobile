import 'package:flutter_test/flutter_test.dart';
import '../lib/bible_models.dart';
import '../lib/sermon_references.dart';
import '../lib/sermon_document.dart';
import '../lib/note_numbering.dart';

void main() {
  final books = [
    BibleBook(bookNumber: 470, name: 'Matius', shortName: 'Mat'),
    BibleBook(bookNumber: 500, name: 'Yohanes', shortName: 'Yoh'),
    BibleBook(bookNumber: 690, name: '1 Yohanes', shortName: '1Yoh'),
    BibleBook(bookNumber: 230, name: 'Mazmur', shortName: 'Mzm'),
    BibleBook(bookNumber: 560, name: 'Efesus', shortName: 'Efesus'),
  ];
  test(
    'Short, full, lowercase, dotted and numbered books resolve to canonical IDs',
    () {
      final matcher = SermonReferenceMatcher(books);
      final text =
          'mat 5:1–3, 5; Matius 5:1; MAT.5:2; Yoh 3:16; 1 Yoh. 4:7-8; Mazm 23:1; Ef 2:8.';
      final links = matcher.find(text);
      expect(links.map((l) => l.reference.bookId), [
        470,
        470,
        470,
        500,
        690,
        230,
        560,
      ]);
      expect(links.first.reference.verses, [1, 2, 3, 5]);
      for (final link in links) {
        expect(text.substring(link.start, link.end), link.text);
      }
      expect(
        matcher.find(
          'Selamat 5:1; Matius 99:1; Mat 5:0; Mat 5:3-1; Mat 5:1000',
        ),
        isEmpty,
      );
    },
  );
  test(
    'References spanning rich formatting remain a single link and headings/numbers survive',
    () {
      final note = NoteModel(
        key: 'n',
        nas: 'Mat 5:1',
        title: 'Khotbah',
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
          {'insert': 'ius 5:1–3 lalu Yoh 3:16.'},
          {'insert': '\n'},
          {'insert': 'Pesan'},
          {
            'insert': '\n',
            'attributes': {'list': 'ordered', noteListStartKey: '100:2'},
          },
        ],
      );
      final paragraphs = sermonParagraphs(note);
      expect(paragraphs.first.isHeading, true);
      expect(
        SermonReferenceMatcher(
          books,
        ).find(paragraphs[1].text).map((l) => l.reference.bookId),
        [470, 500],
      );
      expect(paragraphs.last.marker, '2.');
      expect(paragraphs[1].runs.first.attributes['bold'], true);
    },
  );
}
