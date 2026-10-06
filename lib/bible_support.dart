import 'bible_models.dart';

const String bibleAudioBaseUrl =
    'https://raw.githubusercontent.com/pulicarpus/gereja_mobile/master/audio';

// ID database berbeda dari nomor urut kitab; satu pemetaan untuk semua fitur.
const List<int> bibleBookIds = [
  10,
  20,
  30,
  40,
  50,
  60,
  70,
  80,
  90,
  100,
  110,
  120,
  130,
  140,
  150,
  160,
  190,
  220,
  230,
  240,
  250,
  260,
  290,
  300,
  310,
  330,
  340,
  350,
  360,
  370,
  380,
  390,
  400,
  410,
  420,
  430,
  440,
  450,
  460,
  470,
  480,
  490,
  500,
  510,
  520,
  530,
  540,
  550,
  560,
  570,
  580,
  590,
  600,
  610,
  620,
  630,
  640,
  650,
  660,
  670,
  680,
  690,
  700,
  710,
  720,
  730,
];

int? bibleOrdinal(int bookId) {
  final index = bibleBookIds.indexOf(bookId);
  return index < 0 ? null : index + 1;
}

bool isOldTestament(int bookId) {
  final ordinal = bibleOrdinal(bookId);
  return ordinal != null && ordinal <= 39;
}

String bibleAudioPath(int ordinal, int chapter) {
  final metadata = bibleAudioMap[ordinal];
  final count = bibleChaptersPerBook[ordinal];
  if (metadata == null || count == null || chapter < 1 || chapter > count) {
    throw ArgumentError('Kitab atau pasal audio tidak tersedia.');
  }
  final digits = ordinal == 19 ? 3 : 2;
  return '${metadata['folder']}/${metadata['file']}${chapter.toString().padLeft(digits, '0')}.mp3';
}

String cleanBibleText(String input) {
  return input
      .replaceAll(RegExp(r'<f>.*?</f>', dotAll: true), '')
      .replaceAll(RegExp(r'<(?:pb\s*/|/?t)>'), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'[ \t]*\n(?:[ \t]*\n)*[ \t]*'), '\n')
      .trim();
}

class BibleReference {
  final int bookId;
  final int chapter;
  final List<int> verses;
  const BibleReference(this.bookId, this.chapter, this.verses);

  static BibleReference? parse(String value, List<BibleBook> books) {
    final match = RegExp(r'^\s*(.+?)\s+(\d+):([\d,\s-]+)\s*$')
        .firstMatch(value);
    if (match == null) return null;
    final name = match[1]!.trim().toLowerCase();
    BibleBook? book;
    for (final candidate in books) {
      if (candidate.name.trim().toLowerCase() == name ||
          candidate.shortName.trim().toLowerCase() == name) {
        book = candidate;
        break;
      }
    }
    final chapter = int.tryParse(match[2]!);
    if (book == null || chapter == null || chapter < 1) return null;
    final numbers = <int>{};
    for (final part in match[3]!.split(',')) {
      final range = part.trim().split('-');
      if (range.length > 2) return null;
      final start = int.tryParse(range.first);
      final end = int.tryParse(range.last);
      if (start == null || end == null || start < 1 || end < start || end > 200)
        return null;
      for (var verse = start; verse <= end; verse++) {
        numbers.add(verse);
      }
    }
    if (numbers.isEmpty) return null;
    return BibleReference(book.bookNumber, chapter, numbers.toList()..sort());
  }
}

const Map<int, Map<String, String>> bibleAudioMap = {
  1: {"folder": "kejadian", "file": "01_kej"},
  2: {"folder": "keluaran", "file": "02_kel"},
  3: {"folder": "imamat", "file": "03_ima"},
  4: {"folder": "bilangan", "file": "04_bil"},
  5: {"folder": "ulangan", "file": "05_ula"},
  6: {"folder": "yosua", "file": "06_yos"},
  7: {"folder": "hakim-hakim", "file": "07_hak"},
  8: {"folder": "rut", "file": "08_rut"},
  9: {"folder": "1samuel", "file": "09_1sa"},
  10: {"folder": "2samuel", "file": "10_2sa"},
  11: {"folder": "1raja-raja", "file": "11_1Kings_"},
  12: {"folder": "2raja-raja", "file": "12_2Kings_"},
  13: {"folder": "1tawarikh", "file": "13_1Chronicles_"},
  14: {"folder": "2tawarikh", "file": "14_2Chronicles_"},
  15: {"folder": "ezra", "file": "15_ezr"},
  16: {"folder": "nehemia", "file": "16_neh"},
  17: {"folder": "ester", "file": "17_est"},
  18: {"folder": "ayub", "file": "18_ayb"},
  19: {"folder": "mazmur", "file": "19_mzm"},
  20: {"folder": "amsal", "file": "20_ams"},
  21: {"folder": "pengkhotbah", "file": "21_pkh"},
  22: {"folder": "kidungagung", "file": "22_kid"},
  23: {"folder": "yesaya", "file": "23_yes"},
  24: {"folder": "yeremia", "file": "24_yer"},
  25: {"folder": "ratapan", "file": "25_rat"},
  26: {"folder": "yehezkiel", "file": "26_yeh"},
  27: {"folder": "daniel", "file": "27_dan"},
  28: {"folder": "hosea", "file": "28_hos"},
  29: {"folder": "yoel", "file": "29_yoe"},
  30: {"folder": "amos", "file": "30_amo"},
  31: {"folder": "obaja", "file": "31_oba"},
  32: {"folder": "yunus", "file": "32_yun"},
  33: {"folder": "mikha", "file": "33_mik"},
  34: {"folder": "nahum", "file": "34_nah"},
  35: {"folder": "habakuk", "file": "35_hab"},
  36: {"folder": "zefanya", "file": "36_zef"},
  37: {"folder": "hagai", "file": "37_hag"},
  38: {"folder": "zakharia", "file": "38_zak"},
  39: {"folder": "maleakhi", "file": "39_mal"},
  40: {"folder": "matius", "file": "01_mat"},
  41: {"folder": "markus", "file": "02_mrk"},
  42: {"folder": "lukas", "file": "03_luk"},
  43: {"folder": "yohanes", "file": "04_yoh"},
  44: {"folder": "kisahpararasul", "file": "05_kis"},
  45: {"folder": "roma", "file": "06_rom"},
  46: {"folder": "1korintus", "file": "07_1ko"},
  47: {"folder": "2korintus", "file": "08_2ko"},
  48: {"folder": "galatia", "file": "09_gal"},
  49: {"folder": "efesus", "file": "10_efe"},
  50: {"folder": "filipi", "file": "11_fil"},
  51: {"folder": "kolose", "file": "12_kol"},
  52: {"folder": "1tesalonika", "file": "13_1te"},
  53: {"folder": "2tesalonika", "file": "14_2te"},
  54: {"folder": "1timotius", "file": "15_1ti"},
  55: {"folder": "2timotius", "file": "16_2ti"},
  56: {"folder": "titus", "file": "17_tit"},
  57: {"folder": "filemon", "file": "18_flm"},
  58: {"folder": "ibrani", "file": "19_ibr"},
  59: {"folder": "yakobus", "file": "20_yak"},
  60: {"folder": "1petrus", "file": "21_1pe"},
  61: {"folder": "2petrus", "file": "22_2pe"},
  62: {"folder": "1yohanes", "file": "23_1yo"},
  63: {"folder": "2yohanes", "file": "24_2yo"},
  64: {"folder": "3yohanes", "file": "25_3yo"},
  65: {"folder": "yudas", "file": "26_yud"},
  66: {"folder": "wahyu", "file": "27_wah"},
};

const Map<int, int> bibleChaptersPerBook = {
  1: 50,
  2: 40,
  3: 27,
  4: 36,
  5: 34,
  6: 24,
  7: 21,
  8: 4,
  9: 31,
  10: 24,
  11: 22,
  12: 25,
  13: 29,
  14: 36,
  15: 10,
  16: 13,
  17: 10,
  18: 42,
  19: 150,
  20: 31,
  21: 12,
  22: 8,
  23: 66,
  24: 52,
  25: 5,
  26: 48,
  27: 12,
  28: 14,
  29: 3,
  30: 9,
  31: 1,
  32: 4,
  33: 7,
  34: 3,
  35: 3,
  36: 3,
  37: 2,
  38: 14,
  39: 4,
  40: 28,
  41: 16,
  42: 24,
  43: 21,
  44: 28,
  45: 16,
  46: 16,
  47: 13,
  48: 6,
  49: 6,
  50: 4,
  51: 4,
  52: 5,
  53: 3,
  54: 6,
  55: 4,
  56: 3,
  57: 1,
  58: 13,
  59: 5,
  60: 5,
  61: 3,
  62: 5,
  63: 1,
  64: 1,
  65: 1,
  66: 22,
};

// MP3 dapat diawali tag ID3 atau frame MPEG. Tolak respons HTML/berkas kosong.
bool isMp3Header(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0x49 &&
      bytes[1] == 0x44 &&
      bytes[2] == 0x33)
    return true;
  return bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0;
}
