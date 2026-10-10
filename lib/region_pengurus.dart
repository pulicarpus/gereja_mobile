import 'package:cloud_firestore/cloud_firestore.dart';
import 'region_posts.dart';
import 'region_names.dart';

Future<QueryDocumentSnapshot<Map<String, dynamic>>?> resolveRegionPengurus(
  FirebaseFirestore db,
  String area,
) async {
  final churches = await db.collection('churches').get();
  final records = churches.docs.map((doc) => doc.data()).toList();
  final aliases = regionPostAliases(area, records);
  if (aliases.isEmpty || aliases.length > 30) {
    throw StateError('Nama daerah perlu diperiksa oleh administrator.');
  }
  final roots = await db
      .collection('struktur_pengurus_daerah')
      .where('daerah', whereIn: aliases)
      .get();
  final canonical = churchRegionIdentifier(area, records);
  final docs = roots.docs.toList()
    ..sort((a, b) {
      final aCanonical = a.data()['daerah'] == canonical;
      final bCanonical = b.data()['daerah'] == canonical;
      if (aCanonical != bCanonical) return aCanonical ? -1 : 1;
      return a.id.compareTo(b.id);
    });
  return docs.isEmpty ? null : docs.first;
}
