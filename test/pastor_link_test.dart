import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/pastor_link_service.dart';
import '../lib/management_support.dart';
import '../lib/user_manager.dart';

void main() {
  late FakeFirebaseFirestore db;
  late PastorLinkService service;
  late ManagementRecord account;
  setUp(() async {
    db = FakeFirebaseFirestore();
    UserManager()
      ..userId = 'boss'
      ..userRole = 'superadmin'
      ..activeChurchId = 'A'
      ..originalChurchId = 'A';
    service = PastorLinkService(
      db: db,
      auth: MockFirebaseAuth(mockUser: MockUser(uid: 'boss'), signedIn: true),
    );
    await db.doc('users/boss').set({'role': 'superadmin'});
    await db.doc('users/pastor').set({'role': 'user', 'churchId': 'A'});
    account = ManagementRecord(
      'pastor',
      (await db.doc('users/pastor').get()).data()!,
    );
    await db.doc('churches/A').set({
      'namaGereja': 'Asal',
      'daerah': 'Belitang',
      'gembalaProfiles': [
        {'id': 'first', 'name': 'Pdt. Pertama', 'photo': 'https://foto/first'},
        {'id': 'second', 'name': 'Vic. Kedua'},
      ],
    });
    await db.doc('churches/A/jemaat/member').set({
      'namaLengkap': 'Pertama',
      'tanggalLahir': '01/01/1980',
    });
  });
  test(
    'binds account, member and existing profile without adding duplicate pastors',
    () async {
      await service.link(account, 'member', 'first');
      final linked = (await db.doc('users/pastor').get()).data()!;
      expect(linked['role'], 'admin');
      expect(linked['isPastor'], true);
      expect(linked['pastorId'], 'first');
      expect(linked['jemaatId'], 'member');
      expect(linked['daerah'], 'Belitang');
      expect(
        (await db.doc('churches/A/jemaat/member').get()).data()!['uid'],
        'pastor',
      );
      final profiles =
          (await db.doc('churches/A').get()).data()!['gembalaProfiles'] as List;
      expect(profiles.length, 2);
      expect(profiles.first['uid'], 'pastor');
      expect(profiles.first['photo'], 'https://foto/first');
      expect(profiles.last['id'], 'second');
      final fresh = ManagementRecord('pastor', linked);
      await service.link(fresh, 'member', 'first');
      expect(
        ((await db.doc('churches/A').get()).data()!['gembalaProfiles'] as List)
            .length,
        2,
      );
    },
  );
  test('never steals another member or pastor profile', () async {
    await db.doc('churches/A/jemaat/member').update({'uid': 'other'});
    await expectLater(
      service.link(account, 'member', 'first'),
      throwsStateError,
    );
    expect((await db.doc('users/pastor').get()).data()!['role'], 'user');
    await db.doc('churches/A/jemaat/member').update({'uid': ''});
    await db.doc('churches/A').update({
      'gembalaProfiles': [
        {'id': 'first', 'name': 'Pertama', 'uid': 'other', 'memberId': 'other'},
      ],
    });
    await expectLater(
      service.link(account, 'member', 'first'),
      throwsStateError,
    );
    expect((await db.doc('churches/A/jemaat/member').get()).data()!['uid'], '');
  });
  test(
    'fresh server role prevents local admin linking or granting pastor access',
    () async {
      await db.doc('users/boss').update({'role': 'admin'});
      await expectLater(
        service.link(account, 'member', 'first'),
        throwsStateError,
      );
      expect((await db.doc('users/pastor').get()).data()!['role'], 'user');
    },
  );
  test(
    'legacy profile becomes a stable identity instead of colliding with another primary',
    () async {
      await db.doc('churches/A').set({
        'namaGereja': 'Asal',
        'daerah': 'Belitang',
        'namaGembala': 'Pdt. Pertama',
        'fotoGembalaUrl': 'https://foto/first',
      });
      await service.link(account, 'member', 'legacy-primary');
      final profiles =
          (await db.doc('churches/A').get()).data()!['gembalaProfiles'] as List;
      expect(profiles.single['id'], 'pastor-pastor');
      expect(profiles.single['photo'], 'https://foto/first');
    },
  );
}
