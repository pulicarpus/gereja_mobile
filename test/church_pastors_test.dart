import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/church_pastors.dart';
import '../lib/user_manager.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ChurchPastorsRepository repository;
  const second = ChurchPastor(
    id: 'second',
    name: 'Gembala Kedua',
    wa: '08123456789',
  );
  const third = ChurchPastor(id: 'third', name: 'Gembala Ketiga');
  Future<Map<String, dynamic>> data() async =>
      (await db.doc('churches/C').get()).data()!;
  setUp(() async {
    db = FakeFirebaseFirestore();
    UserManager()
      ..userId = 'admin'
      ..userRole = 'admin'
      ..originalChurchId = 'C'
      ..activeChurchId = 'C';
    repository = ChurchPastorsRepository(
      'C',
      db: db,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'admin')),
    );
    await db.doc('users/admin').set({'role': 'admin', 'churchId': 'C'});
    await db.doc('churches/C').set({
      'namaGereja': 'Gereja Lama',
      'namaGembala': 'Gembala Pertama',
      'fotoGembalaUrl': 'foto-lama',
      'waGembala': '0811111111',
      'fbGembala': 'https://facebook.com/lama',
      'alamat': 'Alamat tetap',
    });
  });
  test(
    'Legacy single profile expands to two or more without losing existing data',
    () async {
      expect(churchPastors(await data()).length, 1);
      await repository.save(second);
      await repository.save(third);
      final church = await data();
      final profiles = churchPastors(church);
      expect(profiles.map((p) => p.name), [
        'Gembala Pertama',
        'Gembala Kedua',
        'Gembala Ketiga',
      ]);
      expect(profiles.first.photo, 'foto-lama');
      expect(profiles.first.fb, 'https://facebook.com/lama');
      expect(profiles[1].wa, '08123456789');
      expect(church['alamat'], 'Alamat tetap');
      expect(church['namaGembala'], 'Gembala Pertama');
      await repository.save(
        third,
      ); // Retrying the same add must not duplicate it.
      expect(churchPastors(await data()).length, 3);
    },
  );
  test(
    'Editing one profile preserves others and rejects a stale edit',
    () async {
      await repository.save(second);
      await repository.save(third);
      const edited = ChurchPastor(id: 'second', name: 'Nama diperbaiki');
      await repository.save(edited, expected: second);
      await expectLater(
        repository.save(second, expected: second),
        throwsStateError,
      );
      expect(churchPastors(await data()).map((p) => p.name), [
        'Gembala Pertama',
        'Nama diperbaiki',
        'Gembala Ketiga',
      ]);
    },
  );
  test(
    'Deletion promotes the next profile; removing all does not resurrect legacy data',
    () async {
      await repository.save(second);
      await repository.save(third);
      await repository.remove(churchPastors(await data()).first);
      expect((await data())['namaGembala'], 'Gembala Kedua');
      await repository.remove(second);
      expect(churchPastors(await data()).single.id, 'third');
      await repository.remove(third);
      expect(churchPastors(await data()), isEmpty);
      expect((await data())['namaGembala'], '');
      expect((await data())['namaGereja'], 'Gereja Lama');
    },
  );
  test(
    'Fresh server permission and active church scope are required',
    () async {
      await db.doc('users/admin').update({'role': 'user'});
      await expectLater(repository.save(second), throwsStateError);
      await db.doc('users/admin').update({'role': 'admin', 'isBlocked': true});
      await expectLater(repository.save(second), throwsStateError);
      await db.doc('users/admin').set({'role': 'admin', 'churchId': 'other'});
      await expectLater(repository.save(second), throwsStateError);
      await db.doc('users/admin').set({'role': 'superadmin'});
      await repository.save(second);
      UserManager().activeChurchId = 'other';
      await expectLater(repository.save(third), throwsStateError);
    },
  );
  test('Blank entries do not create placeholder cards', () {
    expect(churchPastors({}), isEmpty);
    expect(
      churchPastors({
        'gembalaProfiles': [
          {'id': 'empty', 'name': '   '},
          second.toMap(),
        ],
      }).map((p) => p.id),
      ['second'],
    );
    expect(
      churchPastors({'gembalaProfiles': [], 'namaGembala': 'Nama lama'}),
      isEmpty,
    );
  });
}
