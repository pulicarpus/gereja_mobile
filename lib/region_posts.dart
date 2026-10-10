import 'package:cloud_firestore/cloud_firestore.dart';
import 'region_names.dart';

/// Include legacy spellings without rewriting posts or their comment paths.
List<String> regionPostAliases(
  String area,
  Iterable<Map<String, dynamic>> churches,
) => {
  area,
  for (final church in churches)
    if (church['daerah'] is String &&
        regionNameKey(church['daerah']) == regionNameKey(area))
      church['daerah'] as String,
}.where((name) => cleanRegionName(name).isNotEmpty).toList();

Stream<QuerySnapshot<Map<String, dynamic>>> regionPosts(
  FirebaseFirestore db,
  String area, {
  bool includeAliases = true,
}) async* {
  if (!includeAliases) {
    yield* db
        .collection('info_surat_daerah')
        .where('daerah', isEqualTo: area)
        .snapshots();
    return;
  }
  final churches = await db.collection('churches').get();
  final aliases = regionPostAliases(
    area,
    churches.docs.map((doc) => doc.data()),
  );
  if (aliases.isEmpty || aliases.length > 30) {
    throw StateError('Nama daerah perlu diperiksa oleh superadmin.');
  }
  yield* db
      .collection('info_surat_daerah')
      .where('daerah', whereIn: aliases)
      .snapshots();
}
