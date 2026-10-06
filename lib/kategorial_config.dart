class KategorialConfig {
  static const String sekolahMinggu = "Sekolah Minggu";
  static const String amki = "AMKI";
  static const String perkawan = "Perkawan";
  static const String perkaria = "Perkaria";
  static const String lainnya = "Lainnya";

  static const List<String> pelayanan = [
    sekolahMinggu,
    amki,
    perkawan,
    perkaria,
  ];

  static const List<String> pilihanJemaat = [
    sekolahMinggu,
    amki,
    perkawan,
    perkaria,
    lainnya,
  ];

  static String clean(dynamic raw) => raw?.toString().trim() ?? "";

  static String normalized(dynamic raw) => clean(raw).toLowerCase();

  static bool same(dynamic a, dynamic b) =>
      normalized(a) == normalized(b);

  static String? canonicalPelayanan(dynamic raw) {
    final value = normalized(raw);
    for (final item in pelayanan) {
      if (normalized(item) == value) return item;
    }
    return null;
  }

  static String canonicalJemaat(dynamic raw) {
    final value = normalized(raw);
    for (final item in pilihanJemaat) {
      if (normalized(item) == value) return item;
    }
    return lainnya;
  }

  static bool isPelayanan(dynamic raw) =>
      canonicalPelayanan(raw) != null;
}
