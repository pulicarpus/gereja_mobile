import 'package:flutter_test/flutter_test.dart';
import '../lib/bible_models.dart';
import '../lib/bible_support.dart';
import '../lib/bible_translation.dart';

void main() {
  test('References retain their book identity across TB and TL spelling', () {
    final tb = [BibleBook(bookNumber: 360, name: 'Yoël', shortName: 'Yl')];
    final tl = [BibleBook(bookNumber: 360, name: 'Yoel', shortName: 'Yl')];
    expect(BibleReference.parse('Yoël 2:1-3', tl)!.bookId, 360);
    expect(BibleReference.parse('Yoel 2:1-3', tb)!.bookId, 360);
    expect(BibleReference.parse('Yoël 2:1-3', tl)!.verses, [1, 2, 3]);
  });
  test('Only packaged translations can be restored from preferences', () {
    expect(BibleTranslation.fromFile('TJL.SQLite3'), BibleTranslation.tl);
    expect(BibleTranslation.fromFile('TB.SQLite3'), BibleTranslation.tb);
    expect(BibleTranslation.fromFile('../other.sqlite'), BibleTranslation.tb);
    expect(BibleTranslation.fromFile(null), BibleTranslation.tb);
  });
}
