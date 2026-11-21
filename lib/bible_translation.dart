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
