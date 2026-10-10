import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/management_service.dart';
import '../lib/management_support.dart';
import '../lib/region_names.dart';
import '../lib/user_manager.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FirebaseManagementGateway gateway;
  Future<ManagementRecord> church() async =>
      ManagementRecord('C', (await db.doc('churches/C').get()).data()!);
  setUp(() async {
    db = FakeFirebaseFirestore();
    UserManager()
      ..userId = 'boss'
      ..userRole = 'superadmin'
      ..activeChurchId = 'HOME'
      ..originalChurchId = 'HOME';
    gateway = FirebaseManagementGateway(
      db: db,
      auth: MockFirebaseAuth(mockUser: MockUser(uid: 'boss'), signedIn: true),
    );
    await db.doc('users/boss').set({'role': 'superadmin', 'churchId': 'HOME'});
    await db.doc('churches/HOME').set({'namaGereja': 'Home', 'daerah': 'Home'});
    await db.doc('churches/C').set({
      'namaGereja': 'Test',
      'daerah': 'Belitang',
      'kodeUndangan': 'CODE',
    });
  });
  test(
    'Archive hides empty church and disables invitation; restore preserves code',
    () async {
      await gateway.deleteChurch(await church());
      expect((await church()).data['isArchived'], true);
      expect((await church()).data.containsKey('kodeUndangan'), false);
      expect(
        (await gateway.churchChoices()).map((c) => c.id),
        isNot(contains('C')),
      );
      await gateway.restoreChurch(await church());
      expect((await church()).data['kodeUndangan'], 'CODE');
      expect((await gateway.churchChoices()).map((c) => c.id), contains('C'));
    },
  );
  test('Member history blocks archive without changing church', () async {
    await db.doc('churches/C/jemaat/member').set({'namaLengkap': 'Member'});
    await expectLater(gateway.deleteChurch(await church()), throwsStateError);
    expect((await church()).data['isArchived'], isNull);
  });
  test('Rename changes display label while keeping history identity', () async {
    await db.doc('info_surat_daerah/info').set({'daerah': 'Belitang'});
    await gateway.renameRegion('Belitang', 'Belitang Baru');
    expect((await church()).data['daerah'], 'Belitang');
    expect((await church()).data['namaDaerah'], 'Belitang Baru');
    expect(
      (await db.doc('info_surat_daerah/info').get()).data()!['daerah'],
      'Belitang',
    );
    expect(
      churchRegionIdentifier('BELITANG BARU', [(await church()).data]),
      'Belitang',
    );
  });
  test('Regional history blocks deleting region', () async {
    await db.doc('info_surat_daerah/info').set({'daerah': 'Belitang'});
    await expectLater(gateway.deleteRegion('Belitang'), throwsStateError);
    expect((await church()).data['isArchived'], isNull);
  });
  test(
    'Empty region can be archived and disappears from active groups',
    () async {
      await gateway.deleteRegion('Belitang');
      final groups = groupChurchRegions(
        (await db.collection('churches').get()).docs.map((c) => c.data()),
      );
      expect(groups.map((g) => g.name), isNot(contains('Belitang')));
    },
  );
  test('Fresh server role rejects local superadmin privilege', () async {
    await db.doc('users/boss').update({'role': 'user'});
    await expectLater(gateway.deleteChurch(await church()), throwsStateError);
    await expectLater(
      gateway.renameRegion('Belitang', 'Changed'),
      throwsStateError,
    );
  });
}
