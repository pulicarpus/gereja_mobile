import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/family_service.dart';
import '../lib/user_manager.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FamilyService service;
  setUp(() async {
    db = FakeFirebaseFirestore();
    UserManager()
      ..userId = 'admin'
      ..userRole = 'admin'
      ..originalChurchId = 'C'
      ..activeChurchId = 'C';
    service = FamilyService(
      db: db,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'admin')),
    );
    await db.doc('users/admin').set({'role': 'admin', 'churchId': 'C'});
    await db.doc('churches/C/jemaat/head').set({
      'namaLengkap': 'Nama',
      'statusKeluarga': 'Kepala Keluarga',
      'idKepalaKeluarga': 'head',
      'uid': 'linked',
      'fotoProfil': 'photo',
      'tanggalLahir': '01/01/1980',
      'familyRevision': 3,
    });
    await db.doc('users/linked').set({'churchId': 'C', 'jemaatId': 'head'});
  });
  test(
    'Cancels an empty family without deleting personal data or linked account',
    () async {
      await service.cancelHead('C', 'head');
      final data = (await db.doc('churches/C/jemaat/head').get()).data()!;
      expect(data['statusKeluarga'], 'Belum terikat keluarga');
      expect(data['idKepalaKeluarga'], '');
      expect(data['familyRevision'], 4);
      expect(data['namaLengkap'], 'Nama');
      expect(data['uid'], 'linked');
      expect(data['fotoProfil'], 'photo');
      expect(data['tanggalLahir'], '01/01/1980');
      expect((await db.doc('users/linked').get()).data()!['jemaatId'], 'head');
      await expectLater(service.cancelHead('C', 'head'), throwsStateError);
    },
  );
  test('A family with members cannot be detached from its head', () async {
    await db.doc('churches/C/jemaat/child').set({
      'idKepalaKeluarga': 'head',
      'statusKeluarga': 'Anak',
    });
    await expectLater(service.cancelHead('C', 'head'), throwsStateError);
    expect(
      (await db.doc('churches/C/jemaat/head').get()).data()!['statusKeluarga'],
      'Kepala Keluarga',
    );
    expect(
      (await db.doc('churches/C/jemaat/child').get())
          .data()!['idKepalaKeluarga'],
      'head',
    );
  });
  test(
    'Checks server role, blocked status and church scope, not cached admin role',
    () async {
      for (final actor in [
        {'role': 'user', 'churchId': 'C'},
        {'role': 'admin', 'churchId': 'other'},
        {'role': 'superadmin', 'isBlocked': true},
      ]) {
        await db.doc('users/admin').set(actor);
        await expectLater(service.cancelHead('C', 'head'), throwsStateError);
      }
      await db.doc('users/admin').set({'role': 'superadmin'});
      await service.cancelHead('C', 'head');
    },
  );
  test('Rejects a changed active church before writing', () async {
    UserManager().activeChurchId = 'other';
    await expectLater(service.cancelHead('C', 'head'), throwsStateError);
    expect(
      (await db.doc('churches/C/jemaat/head').get())
          .data()!['idKepalaKeluarga'],
      'head',
    );
  });
}
