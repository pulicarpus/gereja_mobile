import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_safety.dart';
import 'user_manager.dart';

class FamilyService {
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  FamilyService({FirebaseFirestore? db, FirebaseAuth? auth})
    : db = db ?? FirebaseFirestore.instance,
      auth = auth ?? FirebaseAuth.instance;

  Future<void> cancelHead(String churchId, String memberId) async {
    final uid = auth.currentUser?.uid;
    void checkSession() {
      if (uid == null ||
          auth.currentUser?.uid != uid ||
          UserManager().userId != uid ||
          UserManager().getChurchIdForCurrentView() != churchId) {
        throw StateError('Sesi atau gereja aktif berubah. Buka ulang halaman.');
      }
    }

    checkSession();
    final actorRef = db.collection('users').doc(uid);
    final actor = await actorRef.get(const GetOptions(source: Source.server));
    if (!actor.exists || !permitsChurchWrite(actor.data()!, churchId)) {
      throw StateError(
        'Hanya admin gereja atau superadmin yang dapat membatalkan kepala keluarga.',
      );
    }
    final members = db
        .collection('churches')
        .doc(churchId)
        .collection('jemaat');
    final ref = members.doc(memberId);
    final before = await ref.get(const GetOptions(source: Source.server));
    final dependents = await members
        .where('idKepalaKeluarga', isEqualTo: memberId)
        .get(const GetOptions(source: Source.server));
    if (dependents.docs.any((doc) => doc.id != memberId)) {
      throw StateError(
        'Masih ada anggota dalam keluarga ini. Pindahkan atau keluarkan anggota terlebih dahulu, lalu batalkan kepala keluarga.',
      );
    }
    await db
        .runTransaction((tx) async {
          final freshActor = await tx.get(actorRef);
          final head = await tx.get(ref);
          checkSession();
          if (!freshActor.exists ||
              !permitsChurchWrite(freshActor.data()!, churchId)) {
            throw StateError('Izin admin sudah berubah.');
          }
          if (!head.exists ||
              head.data()?['statusKeluarga'] != 'Kepala Keluarga' ||
              (legacyText(head.data()?['idKepalaKeluarga']).isNotEmpty &&
                  head.data()?['idKepalaKeluarga'] != memberId) ||
              !before.exists ||
              head.data()?['familyRevision'] !=
                  before.data()?['familyRevision']) {
            throw StateError('Data keluarga sudah berubah. Muat ulang dahulu.');
          }
          tx.update(ref, {
            'idKepalaKeluarga': '',
            'statusKeluarga': 'Belum terikat keluarga',
            'familyRevision': FieldValue.increment(1),
          });
        })
        .timeout(const Duration(seconds: 20));
  }
}
