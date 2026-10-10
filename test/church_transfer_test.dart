import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/management_service.dart';
import '../lib/management_support.dart';
import '../lib/user_manager.dart';

class TransferFirestore extends FakeFirebaseFirestore {
  Future<void> Function()? beforeTransaction;
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final hook = beforeTransaction;
    beforeTransaction = null;
    if (hook != null) await hook();
    return super.runTransaction(
      handler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}

void main() {
  late TransferFirestore db;
  late FirebaseManagementGateway gateway;
  late ManagementRecord expected;
  setUp(() async {
    db = TransferFirestore();
    UserManager()
      ..userId = 'boss'
      ..userRole = 'superadmin'
      ..activeChurchId = 'A'
      ..originalChurchId = 'A';
    gateway = FirebaseManagementGateway(
      db: db,
      auth: MockFirebaseAuth(mockUser: MockUser(uid: 'boss'), signedIn: true),
    );
    await db.doc('users/boss').set({'role': 'superadmin', 'churchId': 'A'});
    await db.doc('churches/A').set({'namaGereja': 'Asal', 'daerah': 'Lama'});
    await db.doc('churches/B').set({'namaGereja': 'Tujuan', 'daerah': 'Baru'});
    for (final id in ['head', 'child', 'unlinked']) {
      await db.doc('churches/A/jemaat/$id').set({
        'id': id,
        'namaLengkap': id,
        'idKepalaKeluarga': 'head',
        'statusKeluarga': id == 'head' ? 'Kepala Keluarga' : 'Anak',
        'kelompok': 'AMKI',
        'foto': 'https://foto/$id',
        'custom': {'keep': true},
        if (id != 'unlinked') 'uid': id,
      });
      if (id != 'unlinked') {
        await db.doc('users/$id').set({
          'role': id == 'head' ? 'gembala' : 'admin',
          'churchId': 'A',
          'jemaatId': id,
          'kelompok': 'AMKI',
          'isPengurus': true,
          'adminDaerahArea': 'Lama',
        });
      }
    }
    expected = ManagementRecord(
      'child',
      (await db.doc('users/child').get()).data()!,
    );
  });
  test(
    'One person moves full biodata and account, leaves relatives in source',
    () async {
      final original = (await db.doc('churches/A/jemaat/child').get()).data()!;
      await gateway.changeUser(
        expected,
        'churchId',
        const ChurchTransferChoice('B'),
      );
      expect((await db.doc('churches/A/jemaat/child').get()).exists, false);
      expect((await db.doc('churches/B/jemaat/child').get()).data(), {
        ...original,
        'idKepalaKeluarga': 'child',
        'statusKeluarga': 'Kepala Keluarga',
      });
      expect((await db.doc('churches/A/jemaat/head').get()).exists, true);
      final account = (await db.doc('users/child').get()).data()!;
      expect(account['churchId'], 'B');
      expect(account['jemaatId'], 'child');
      expect(account['role'], 'user');
      expect(account['kelompok'], 'AMKI');
      expect(account['isPengurus'], false);
      expect(account['adminDaerahArea'], '');
    },
  );
  test(
    'Whole family includes unlinked relatives and all linked accounts',
    () async {
      await gateway.changeUser(
        expected,
        'churchId',
        const ChurchTransferChoice('B', wholeFamily: true),
      );
      for (final id in ['head', 'child', 'unlinked']) {
        expect((await db.doc('churches/A/jemaat/$id').get()).exists, false);
        final moved = (await db.doc('churches/B/jemaat/$id').get()).data()!;
        expect(moved['idKepalaKeluarga'], 'head');
        expect(moved['custom'], {'keep': true});
      }
      final pastor = (await db.doc('users/head').get()).data()!;
      expect(pastor['churchId'], 'B');
      expect(pastor['jemaatId'], 'head');
      expect(pastor['role'], 'gembala');
      expect(pastor['daerah'], 'Baru');
      expect(pastor['adminDaerahArea'], '');
    },
  );
  test(
    'Family changed after preflight cancels transfer without leaving new member behind',
    () async {
      db.beforeTransaction = () async {
        await db.doc('churches/A/jemaat/new').set({'idKepalaKeluarga': 'head'});
        await db.doc('churches/A/jemaat/head').update({'familyRevision': 1});
      };
      await expectLater(
        gateway.changeUser(
          expected,
          'churchId',
          const ChurchTransferChoice('B', wholeFamily: true),
        ),
        throwsStateError,
      );
      expect((await db.doc('churches/A/jemaat/new').get()).exists, true);
      expect((await db.doc('churches/A/jemaat/child').get()).exists, true);
      expect((await db.doc('churches/B/jemaat/child').get()).exists, false);
    },
  );
  test('Head cannot leave dependents behind when moving alone', () async {
    final head = ManagementRecord(
      'head',
      (await db.doc('users/head').get()).data()!,
    );
    await expectLater(
      gateway.changeUser(head, 'churchId', const ChurchTransferChoice('B')),
      throwsStateError,
    );
    expect((await db.doc('users/head').get()).data()!['churchId'], 'A');
  });
  test('Destination collision aborts all family writes', () async {
    await db.doc('churches/B/jemaat/unlinked').set({'namaLengkap': 'Other'});
    await expectLater(
      gateway.changeUser(
        expected,
        'churchId',
        const ChurchTransferChoice('B', wholeFamily: true),
      ),
      throwsStateError,
    );
    expect((await db.doc('churches/A/jemaat/child').get()).exists, true);
    expect((await db.doc('churches/B/jemaat/child').get()).exists, false);
    expect((await db.doc('users/child').get()).data()!['churchId'], 'A');
  });
  test('Broken account ownership aborts all family writes', () async {
    await db.doc('users/head').update({'jemaatId': 'other'});
    await expectLater(
      gateway.changeUser(
        expected,
        'churchId',
        const ChurchTransferChoice('B', wholeFamily: true),
      ),
      throwsStateError,
    );
    expect((await db.doc('churches/A/jemaat/head').get()).exists, true);
    expect((await db.doc('churches/B/jemaat/child').get()).exists, false);
  });
  test('Protected superadmin in family aborts transfer', () async {
    await db.doc('users/head').update({'role': 'superadmin'});
    await expectLater(
      gateway.changeUser(
        expected,
        'churchId',
        const ChurchTransferChoice('B', wholeFamily: true),
      ),
      throwsStateError,
    );
    expect((await db.doc('users/child').get()).data()!['churchId'], 'A');
  });
}
