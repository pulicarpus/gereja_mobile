import 'package:cloud_firestore/cloud_firestore.dart';
import 'kategorial_config.dart';

/// Derives membership without writing to users or jemaat. A linked record must
/// belong to this UID; stale account categories must not grant another room.
Map<String, dynamic> effectiveKategorialIdentity(
  String uid,
  Map<String, dynamic> account,
  Map<String, dynamic>? member,
) {
  final result = Map<String, dynamic>.from(account);
  final linked = (account['jemaatId']?.toString().trim() ?? '').isNotEmpty;
  if (linked) {
    final ownsLink = member != null && member['uid']?.toString().trim() == uid;
    final category =
        ownsLink
            ? KategorialConfig.canonicalJemaat(member?['kelompok'])
            : KategorialConfig.lainnya;
    result['kelompok'] = category;
    result['isPengurus'] =
        ownsLink &&
        account['isPengurus'] == true &&
        KategorialConfig.same(account['kelompok'], category);
  }
  if (account['isBlocked'] == true) {
    result['kelompok'] = KategorialConfig.lainnya;
    result['isPengurus'] = false;
  }
  return result;
}

Future<Map<String, dynamic>?> readKategorialIdentity(
  FirebaseFirestore db,
  String uid, {
  Transaction? transaction,
}) async {
  Future<DocumentSnapshot<Map<String, dynamic>>> read(
    DocumentReference<Map<String, dynamic>> ref,
  ) =>
      transaction != null
          ? transaction.get(ref)
          : ref
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 20));
  final user = await read(db.collection('users').doc(uid));
  if (!user.exists) return null;
  final account = user.data()!;
  final church = account['churchId']?.toString().trim() ?? '';
  final memberId = account['jemaatId']?.toString().trim() ?? '';
  Map<String, dynamic>? member;
  if (church.isNotEmpty &&
      !church.contains('/') &&
      memberId.isNotEmpty &&
      !memberId.contains('/')) {
    member =
        (await read(
          db
              .collection('churches')
              .doc(church)
              .collection('jemaat')
              .doc(memberId),
        )).data();
  }
  return effectiveKategorialIdentity(uid, account, member);
}
