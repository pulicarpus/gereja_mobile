// Pemeriksaan tanpa Flutter/network. Argumen: fixture JSON dari aset TB dan tree audio.
import 'dart:convert';
import 'dart:io';

import '../lib/bible_models.dart';
import '../lib/bible_support.dart';
import '../lib/ayat_data.dart';

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

void main(List<String> args) {
  final fixture = jsonDecode(File(args.single).readAsStringSync()) as Map;
  final rows = fixture['books'] as List;
  final books = rows
      .map(
        (row) => BibleBook(
          bookNumber: row['id'] as int,
          name: row['name'] as String,
          shortName: row['short'] as String,
        ),
      )
      .toList();
  final audioPaths = (fixture['audioPaths'] as List).cast<String>().toSet();
  var audio = 0;
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    final id = row['id'] as int;
    check(bibleOrdinal(id) == index + 1, 'Pemetaan kitab $id');
    check(isOldTestament(id) == (index < 39), 'Cakupan PL/PB $id');
    check(
      bibleChaptersPerBook[index + 1] == row['chapters'],
      'Jumlah pasal $id',
    );
    for (var chapter = 1; chapter <= (row['chapters'] as int); chapter++) {
      check(
        audioPaths.contains('audio/${bibleAudioPath(index + 1, chapter)}'),
        'Audio $id pasal $chapter',
      );
      audio++;
    }
  }
  final daily = fixture['daily'] as List;
  check(
    AyatData.daftarAyat.length == daily.length,
    'Jumlah referensi ayat harian',
  );
  for (var index = 0; index < daily.length; index++) {
    final actual = AyatData.daftarAyat[index];
    final expected = daily[index];
    check(actual['ref'] == expected['ref'], 'Referensi ayat harian $index');
    // Bandingkan isi terhadap database, mengabaikan whitespace puisi dan markup.
    final normalizedActual = cleanBibleText(actual['isi']!)
        .replaceAll(RegExp(r'\s+'), ' ');
    final normalizedExpected = cleanBibleText(expected['raw'] as String)
        .replaceAll(RegExp(r'\s+'), ' ');
    check(normalizedActual == normalizedExpected, 'Isi ayat harian $index');
  }
  final ref = BibleReference.parse('Yohanes 3:1-3, 5, 7-8', books)!;
  check(ref.verses.join(',') == '1,2,3,5,7,8', 'Referensi multi rentang');
  check(
    BibleReference.parse('2 Yohanes 1:4', books)!.bookId == 700,
    'Nama kitab whitespace',
  );
  check(
    BibleReference.parse('Yohanes 3:5-2', books) == null,
    'Rentang terbalik',
  );
  check(
    BibleReference.parse('Yohanes 3:1,', books) == null,
    'Referensi parsial',
  );
  check(
    cleanBibleText('<f>ⓐ </f>Yesus <J>berkata</J>') == 'Yesus berkata',
    'Catatan kaki dan tag perkataan',
  );
  check(
    cleanBibleText('<t>baris satu</t> <t>baris dua</t>') ==
        'baris satu\nbaris dua',
    'Format puisi',
  );
  final note = NoteModel.fromRaw(
    'Note_1',
    'Yohanes 3:16~|~Judul~|~P~|~D~|~ ~|~awal~|~akhir',
  );
  check(note.content == 'awal~|~akhir', 'Isi catatan legacy');
  final restored = NoteModel.fromRaw(note.key, note.toLocalJson());
  check(
    restored.toLegacyRaw() == note.toLegacyRaw(),
    'Round-trip backup APK lama',
  );
  check(
    AyatData.getAyatHariIni(DateTime(2026, 10, 6)) ==
        AyatData.getAyatHariIni(DateTime(2026, 10, 6, 23, 59)),
    'Kestabilan tanggal ayat',
  );
  check(isMp3Header([0x49, 0x44, 0x33]), 'Header ID3');
  check(!isMp3Header('<html>'.codeUnits), 'Tolak HTML sebagai MP3');
  print(
    'PASS: 66 pemetaan kitab, $audio jalur audio, ${daily.length} ayat harian; '
    'referensi, format teks, backup legacy, tanggal, dan validasi MP3.',
  );
}
