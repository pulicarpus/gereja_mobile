import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/region_pengurus.dart';

void main() {
  test(
    'Pastor resolves the existing canonical board, not an uppercase empty path',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('churches/a').set({'daerah': 'Belitang'});
      await db.doc('churches/b').set({'daerah': 'Belitang'});
      await db.doc('churches/c').set({'daerah': 'BELITANG'});
      await db.doc('struktur_pengurus_daerah/Belitang').set({
        'daerah': 'Belitang',
        'bphd_ketua': 'Ketua',
      });
      await db.doc('struktur_pengurus_daerah/Belitang/penasehat/a').set({
        'nama': 'Penasehat',
      });
      final root = await resolveRegionPengurus(db, 'BELITANG');
      expect(root!.id, 'Belitang');
      expect(root.data()['bphd_ketua'], 'Ketua');
      expect(
        (await root.reference.collection('penasehat').get()).docs.length,
        1,
      );
      expect(await resolveRegionPengurus(db, 'Ketungau'), isNull);
    },
  );
}
