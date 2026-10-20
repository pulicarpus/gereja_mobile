import 'church_pastors.dart';
import 'management_support.dart';

ChurchPastor takeTransferredPastor(
  List<ChurchPastor> source,
  Map<String, dynamic> account,
  String uid,
  String memberId,
) {
  final matches = source
      .where(
        (p) =>
            p.uid == uid ||
            (managementText(account['pastorId']).isNotEmpty &&
                p.id == account['pastorId']),
      )
      .toList();
  if (matches.length != 1 ||
      matches.single.uid != uid ||
      matches.single.memberId != memberId) {
    throw StateError(
      'Hubungkan akun ke profil gembala terlebih dahulu melalui Hubungkan Gembala.',
    );
  }
  final profile = matches.single;
  source.removeWhere((p) => p.id == profile.id);
  return profile;
}
