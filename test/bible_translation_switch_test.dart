import 'package:flutter_test/flutter_test.dart';

import '../lib/bible_translation.dart';

void main() {
  test('TB -> TL retains current book/chapter, starting at verse one', () {
    final target = sameChapterTranslationTarget(470, 1);
    expect(target.bookNumber, 470);
    expect(target.chapter, 1);
    expect(target.verse, 1); // Even when source was Matius 1:2 or 1:16.
  });

  test('Switches keep non-Matius chapters, independent of saved TL position', () {
    final target = sameChapterTranslationTarget(500, 3);
    expect(target.bookNumber, 500);
    expect(target.chapter, 3);
    expect(target.verse, 1);
  });

  test('An imported Mualang catalog is the authority for unsupported books', () {
    const available = <int>{470, 480, 500, 640, 730};
    expect(bibleChapterAvailability(470, 1, available, [1, 2, 3]),
        BibleChapterAvailability.available);
    expect(bibleChapterAvailability(10, 1, available, [1]),
        BibleChapterAvailability.missingBook); // Old Testament.
    expect(bibleChapterAvailability(650, 1, available, [1]),
        BibleChapterAvailability.missingBook); // Not necessarily Mualang.
    expect(bibleChapterAvailability(720, 1, available, [1]),
        BibleChapterAvailability.missingBook); // Yudas.
    expect(bibleChapterAvailability(470, 99, available, [1, 2, 3]),
        BibleChapterAvailability.missingChapter);
  });

  test('Invalid destination numbers cannot silently navigate elsewhere', () {
    expect(() => sameChapterTranslationTarget(-1, 3), throwsArgumentError);
    expect(() => sameChapterTranslationTarget(470, 0), throwsArgumentError);
  });
}
