enum BibleTranslation {
  tb('TB.SQLite3', 'TB', 'Terjemahan Baru'),
  tl('TJL.SQLite3', 'TL', 'Terjemahan Lama');

  final String databaseFile, code, label;
  const BibleTranslation(this.databaseFile, this.code, this.label);
  static BibleTranslation fromFile(String? file) => values.firstWhere(
    (version) => version.databaseFile == file,
    orElse: () => tb,
  );
}
