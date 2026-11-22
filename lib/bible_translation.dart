enum BibleTranslation {
  tb('TB.SQLite3', 'TB', 'Terjemahan Baru'),
  tl('TJL.SQLite3', 'TL', 'Terjemahan Lama'),
  mualang('MUALANG.SQLite3', 'MUL', 'Perjanjian Baru Mualang');

  final String databaseFile, code, label;
  const BibleTranslation(this.databaseFile, this.code, this.label);
  static BibleTranslation fromFile(String? file) => values.firstWhere(
    (version) => version.databaseFile == file,
    orElse: () => tb,
  );
}

/// When changing TB, TL or Mualang, retain the current kitab/pasal and
/// open from ayat 1. Positions saved by an older version are not used.
class BibleTranslationTarget {
  final int bookNumber;
  final int chapter;
  final int verse;
  const BibleTranslationTarget({
    required this.bookNumber,
    required this.chapter,
    required this.verse,
  });
}

BibleTranslationTarget sameChapterTranslationTarget(
    int bookNumber, int chapter) {
  if (bookNumber <= 0 || chapter <= 0) {
    throw ArgumentError('Nomor kitab dan pasal harus positif.');
  }
  return BibleTranslationTarget(
      bookNumber: bookNumber, chapter: chapter, verse: 1);
}

enum BibleChapterAvailability { available, missingBook, missingChapter }

/// This predicate is fed by the books/verses tables of the selected SQLite,
/// rather than assuming that every PB book exists in Mualang.
BibleChapterAvailability bibleChapterAvailability(
    int bookNumber,
    int chapter,
    Iterable<int> availableBooks,
    Iterable<int> availableChapters) {
  if (!availableBooks.contains(bookNumber)) {
    return BibleChapterAvailability.missingBook;
  }
  if (!availableChapters.contains(chapter)) {
    return BibleChapterAvailability.missingChapter;
  }
  return BibleChapterAvailability.available;
}
