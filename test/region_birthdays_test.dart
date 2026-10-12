import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/region_birthdays.dart';

void main() {
  test(
    'Only pastors and regional board members, deduplicated across roles',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('churches/a').set({
        'daerah': 'Belitang',
        'namaGereja': 'Gereja A',
      });
      await db.doc('churches/b').set({'daerah': 'BELITANG'});
      await db.doc('churches/other').set({'daerah': 'Ketungau'});
      await db.doc('churches/a/jemaat/p').set({
        'namaLengkap': 'Pendeta',
        'uid': 'p',
        'tanggalLahir': '12/10/1980',
      });
      await db.doc('churches/a/jemaat/j').set({
        'namaLengkap': 'Jemaat biasa',
        'tanggalLahir': '15/10/1990',
      });
      await db.doc('users/p').set({
        'role': 'gembala',
        'churchId': 'a',
        'jemaatId': 'p',
      });
      await db.doc('struktur_pengurus_daerah/Belitang').set({
        'daerah': 'Belitang',
        'bphd_ketua': 'Pendeta',
        'bphd_sek1': 'Sekretaris',
        'lahir_sek1': '17/10/1985',
        'bphd_bend1': 'Bendahara',
        'lahir_bend1': '17/11/1985',
      });
      await db.doc('struktur_pengurus_daerah/Belitang/komisi/anak').set({
        'namaKomisi': 'Anak',
        'ketua_nama': 'Ketua Anak',
        'ketua_lahir': '18/10/1985',
        'anggota': [
          {'nama': 'Anggota', 'tanggalLahir': '19/10/1985'},
        ],
      });
      final result = await loadRegionalBirthdays(
        db,
        'BELITANG',
        DateTime(2026, 10, 12),
      );
      expect(result.map((r) => r.person['namaLengkap']), [
        'Pendeta',
        'Sekretaris',
        'Ketua Anak',
        'Anggota',
      ]);
      expect(result.first.roles, {'Gembala', 'Ketua BPHD'});
      expect(regionalBirthDate('31/02/1980'), isNull);
    },
  );
}
