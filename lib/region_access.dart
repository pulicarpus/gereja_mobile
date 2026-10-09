import 'package:cloud_firestore/cloud_firestore.dart';
import 'pengurus_support.dart';

/// Reads the authoritative church region; never trusts a stale account region.
Future<String?> linkedPastorRegion(
  Map<String, dynamic> account,
  String uid,
) async {
  if (account['role'] != 'gembala') {
    return pengurusText(account['daerah']).trim();
  }
  final churchId = pengurusText(account['churchId']).trim();
  final memberId = pengurusText(account['jemaatId']).trim();
  if (!pengurusValidId(churchId) ||
      !pengurusValidId(memberId) ||
      account['isBlocked'] == true)
    return null;
  final church = FirebaseFirestore.instance
      .collection('churches')
      .doc(churchId);
  final snapshots = await Future.wait([
    church.get(const GetOptions(source: Source.server)),
    church
        .collection('jemaat')
        .doc(memberId)
        .get(const GetOptions(source: Source.server)),
  ]).timeout(const Duration(seconds: 20));
  if (!snapshots[0].exists ||
      !snapshots[1].exists ||
      snapshots[1].data()?['uid'] != uid)
    return null;
  final area = pengurusText(snapshots[0].data()?['daerah']).trim();
  return area.isEmpty ? null : area;
}
