import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/region_posts.dart';

void main() {
  test('Pastor and superadmin see the same legacy regional posts', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('churches/a').set({'daerah': 'Belitang'});
    await db.doc('churches/b').set({'daerah': ' BELITANG '});
    await db.doc('churches/c').set({'daerah': 'Ketungau'});
    await db.doc('info_surat_daerah/old').set({'daerah': 'Belitang'});
    await db.doc('info_surat_daerah/new').set({'daerah': ' BELITANG '});
    await db.doc('info_surat_daerah/other').set({'daerah': 'Ketungau'});
    for (final area in ['Belitang', ' BELITANG ']) {
      final result = await regionPosts(db, area).first;
      expect(result.docs.map((doc) => doc.id).toSet(), {'old', 'new'});
      expect(result.docs.first.data()['daerah'], isNotNull);
    }
  });
}
