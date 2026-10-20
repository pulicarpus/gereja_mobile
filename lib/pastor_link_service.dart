import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'church_pastors.dart';
import 'management_support.dart';
import 'user_manager.dart';

class PastorLinkService {
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  PastorLinkService({FirebaseFirestore? db, FirebaseAuth? auth})
    : db = db ?? FirebaseFirestore.instance,
      auth = auth ?? FirebaseAuth.instance;

  Future<void> link(
    ManagementRecord expected,
    String memberId,
    String profileId,
  ) async {
    final uid = auth.currentUser?.uid;
    final churchId = managementText(expected.data['churchId']);
    void guard() {
      if (uid == null ||
          auth.currentUser?.uid != uid ||
          UserManager().userId != uid ||
          UserManager().getChurchIdForCurrentView() != churchId) {
        throw StateError(
          'Sesi atau konteks gereja berubah. Buka ulang halaman.',
        );
      }
    }

    guard();
    if (!managementId(churchId) || !managementId(memberId)) {
      throw StateError('Gereja dan Data Jemaat wajib dipilih.');
    }
    await db
        .runTransaction((tx) async {
          final actor = await tx.get(db.doc('users/$uid'));
          final accountRef = db.doc('users/${expected.id}');
          final account = await tx.get(accountRef);
          final churchRef = db.doc('churches/$churchId');
          final church = await tx.get(churchRef);
          final memberRef = churchRef.collection('jemaat').doc(memberId);
          final member = await tx.get(memberRef);
          guard();
          if (actor.data()?['role'] != 'superadmin' ||
              actor.data()?['isBlocked'] == true) {
            throw StateError(
              'Hanya superadmin dapat menautkan gembala dan hak admin.',
            );
          }
          if (!account.exists ||
              account.data()?['role'] == 'superadmin' ||
              account.data()?['isBlocked'] == true ||
              !managementUnchanged(expected.data, account.data()!, [
                'churchId',
                'jemaatId',
                'role',
                'pastorId',
                'isPastor',
              ])) {
            throw StateError(
              'Akun berubah atau tidak dapat ditautkan. Muat ulang.',
            );
          }
          if (!church.exists ||
              church.data()?['isArchived'] == true ||
              managementText(church.data()?['daerah']).isEmpty ||
              !member.exists ||
              member.data()?['status'] == 'Meninggal') {
            throw StateError(
              'Gereja, daerah, atau Data Jemaat tidak tersedia.',
            );
          }
          final oldMember = managementText(account.data()?['jemaatId']);
          final owner = managementText(member.data()?['uid']);
          if ((oldMember.isNotEmpty && oldMember != memberId) ||
              (owner.isNotEmpty && owner != expected.id)) {
            throw StateError(
              'Akun atau Data Jemaat sudah terhubung ke orang lain.',
            );
          }
          final profiles = churchPastors(church.data()!);
          final owned = profiles.where((p) => p.uid == expected.id).toList();
          if (owned.isNotEmpty &&
              (owned.length != 1 || owned.single.id != profileId)) {
            throw StateError(
              'Akun sudah terhubung ke profil lain. Pilih profil tersebut.',
            );
          }
          final index = profiles.indexWhere((p) => p.id == profileId);
          if (profileId.isNotEmpty && index < 0) {
            throw StateError('Profil gembala berubah. Muat ulang pilihan.');
          }
          if (profileId.isEmpty && profiles.isNotEmpty) {
            throw StateError(
              'Pilih profil yang sudah ada atau tambahkan profil melalui halaman utama dahulu.',
            );
          }
          final previous = index < 0 ? null : profiles[index];
          if (previous != null &&
              previous.uid.isNotEmpty &&
              previous.uid != expected.id) {
            throw StateError('Profil sudah terhubung ke akun lain.');
          }
          final profile = ChurchPastor.fromMap({
            if (previous != null) ...previous.toMap(),
            'id': previous == null || previous.id == 'legacy-primary'
                ? 'pastor-${expected.id}'
                : previous.id,
            'name':
                previous?.name ?? managementText(member.data()?['namaLengkap']),
            'photo':
                previous?.photo ??
                managementText(
                  member.data()?['fotoProfil'],
                  managementText(member.data()?['foto']),
                ),
            'uid': expected.id,
            'memberId': memberId,
            'wa':
                previous?.wa ?? managementText(member.data()?['nomorTelepon']),
          });
          if (profile.name.isEmpty)
            throw StateError('Nama jemaat belum diisi.');
          if (index < 0) {
            profiles.add(profile);
          } else {
            profiles[index] = profile;
          }
          tx.update(memberRef, {'uid': expected.id});
          tx.update(accountRef, {
            'jemaatId': memberId,
            'pastorId': profile.id,
            'isPastor': true,
            'role': 'admin',
            'isPengurus': false,
            'kelompok':
                member.data()?['kelompok'] ??
                account.data()?['kelompok'] ??
                'Umum',
            'churchName': managementChurchName(church.data()!),
            'daerah': managementText(church.data()?['daerah']),
          });
          tx.update(churchRef, churchPastorPatch(profiles));
        })
        .timeout(const Duration(seconds: 20));
  }
}
