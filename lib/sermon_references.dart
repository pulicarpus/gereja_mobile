import 'bible_models.dart';
import 'bible_support.dart';

class SermonVerseLink {
  final int start, end;
  final String text, title;
  final BibleReference reference;
  const SermonVerseLink(
    this.start,
    this.end,
    this.text,
    this.title,
    this.reference,
  );
}

/// Recognizes both the database's names and common Indonesian abbreviations.
class SermonReferenceMatcher {
  final Map<String, BibleBook> _aliases = {};
  late final RegExp _pattern;
  SermonReferenceMatcher(List<BibleBook> books) {
    for (final book in books) {
      final aliases = [book.name, book.shortName, ...?_extra[book.bookNumber]];
      for (final alias in aliases) {
        _aliases[_key(alias)] = book;
      }
    }
    final names = _aliases.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final alternatives = names
        .map((name) {
          final numbered = RegExp(r'^([123])(.+)$').firstMatch(name);
          final body = numbered == null
              ? RegExp.escape(name)
              : '${numbered[1]}\\s*${RegExp.escape(numbered[2]!)}';
          return body.replaceAll(' ', r'\s+').replaceAll('e', '[eë]');
        })
        .join('|');
    _pattern = RegExp(
      r'(?<![A-Za-zÀ-ÿ0-9])(' +
          (alternatives.isEmpty ? r'(?!)' : alternatives) +
          r')\.?\s*(\d{1,3})\s*:\s*(\d{1,3}(?:\s*[-–—]\s*\d{1,3})?(?:\s*,\s*\d{1,3}(?:\s*[-–—]\s*\d{1,3})?)*)(?!\d)',
      caseSensitive: false,
    );
  }
  static String _key(String name) => normalizedBibleBookName(name)
      .replaceAll('.', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceFirstMapped(RegExp(r'^([123])\s+'), (m) => m[1]!);

  List<SermonVerseLink> find(String text) {
    final links = <SermonVerseLink>[];
    for (final match in _pattern.allMatches(text)) {
      final book = _aliases[_key(match[1]!)];
      if (book == null) continue;
      final chapter = int.parse(match[2]!);
      final maxChapter = bibleChaptersPerBook[bibleOrdinal(book.bookNumber)];
      if (maxChapter == null || chapter < 1 || chapter > maxChapter) continue;
      final verses = match[3]!
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll(RegExp('[–—]'), '-');
      final reference = BibleReference.parse('${book.name} $chapter:$verses', [
        book,
      ]);
      if (reference == null) continue;
      links.add(
        SermonVerseLink(
          match.start,
          match.end,
          match[0]!,
          '${book.name} $chapter:$verses',
          reference,
        ),
      );
    }
    return links;
  }
}

const Map<int, List<String>> _extra = {
  10: ['Kej'],
  20: ['Kel'],
  30: ['Ima'],
  40: ['Bil'],
  50: ['Ula'],
  60: ['Yos'],
  70: ['Hak'],
  90: ['1 Sam'],
  100: ['2 Sam'],
  110: ['1 Raja', '1 Raj'],
  120: ['2 Raja', '2 Raj'],
  130: ['1 Taw'],
  140: ['2 Taw'],
  150: ['Ezr'],
  160: ['Neh'],
  190: ['Est'],
  220: ['Ayub', 'Ayb'],
  230: ['Maz', 'Mazm', 'Mzm', 'Mazmur'],
  240: ['Ams'],
  250: ['Pkh', 'Png'],
  260: ['Kid', 'Kidung'],
  290: ['Yes'],
  300: ['Yer'],
  310: ['Rat'],
  330: ['Yeh'],
  340: ['Dan'],
  350: ['Hos'],
  360: ['Yoel', 'Yoël'],
  370: ['Am'],
  380: ['Ob'],
  390: ['Yun'],
  400: ['Mik'],
  410: ['Nah'],
  420: ['Hab'],
  430: ['Zef'],
  440: ['Hag'],
  450: ['Zak', 'Za'],
  460: ['Mal'],
  470: ['Mat', 'Matius'],
  480: ['Mar', 'Mrk', 'Markus'],
  490: ['Luk'],
  500: ['Yoh', 'Yohanes'],
  510: ['Kis', 'Kisah', 'Kisah Rasul'],
  520: ['Rom', 'Roma'],
  530: ['1 Kor'],
  540: ['2 Kor'],
  550: ['Gal'],
  560: ['Ef', 'Efe'],
  570: ['Fil', 'Flp'],
  580: ['Kol'],
  590: ['1 Tes'],
  600: ['2 Tes'],
  610: ['1 Tim'],
  620: ['2 Tim'],
  630: ['Tit'],
  640: ['Flm', 'Filem'],
  650: ['Ibr'],
  660: ['Yak'],
  670: ['1 Pet', '1 Ptr'],
  680: ['2 Pet', '2 Ptr'],
  690: ['1 Yoh'],
  700: ['2 Yoh'],
  710: ['3 Yoh'],
  720: ['Yud'],
  730: ['Why', 'Wah'],
};
