import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/kategorial_identity.dart';
import '../lib/app_safety.dart';

void main() {
  test(
    'Old linked AMKI accounts can chat using member category without changing Firebase records',
    () async {
      final db = FakeFirebaseFirestore();
      final account = {
        'churchId': 'a',
        'jemaatId': 'j',
        'kelompok': 'Umum',
        'role': 'user',
        'isPengurus': true,
      };
      final member = {
        'uid': 'u',
        'kelompok': ' amki ',
        'namaLengkap': 'Anggota',
      };
      await db.doc('users/u').set(account);
      await db.doc('churches/a/jemaat/j').set(member);
      final resolved = await readKategorialIdentity(db, 'u');
      expect(permitsRoomAccess(resolved!, 'a', 'AMKI'), isTrue);
      expect(permitsRoomAccess(resolved, 'a', 'Perkaria'), isFalse);
      expect(permitsChurchWrite(resolved, 'a', category: 'AMKI'), isFalse);
      expect((await db.doc('users/u').get()).data(), account);
      expect((await db.doc('churches/a/jemaat/j').get()).data(), member);
      // Sending/editing/deleting use the same resolution inside their transaction.
      await db.runTransaction((tx) async {
        final actor = await readKategorialIdentity(db, 'u', transaction: tx);
        expect(permitsRoomAccess(actor!, 'a', 'AMKI'), isTrue);
      });
      await db.doc('churches/a/jemaat/j').update({'kelompok': 'Perkaria'});
      final changed = await readKategorialIdentity(db, 'u');
      expect(permitsRoomAccess(changed!, 'a', 'AMKI'), isFalse);
      expect(permitsRoomAccess(changed, 'a', 'Perkaria'), isTrue);
      expect((await db.doc('users/u').get()).data(), account);
    },
  );

  test(
    'Mismatched links, missing members and blocked accounts cannot grant AMKI access',
    () {
      final account = {
        'churchId': 'a',
        'jemaatId': 'j',
        'kelompok': 'AMKI',
        'role': 'user',
        'isPengurus': true,
      };
      for (final member in [
        null,
        {'uid': 'other', 'kelompok': 'AMKI'},
        {'kelompok': 'AMKI'},
      ]) {
        final resolved = effectiveKategorialIdentity('u', account, member);
        expect(permitsRoomAccess(resolved, 'a', 'AMKI'), isFalse);
        expect(resolved['isPengurus'], isFalse);
      }
      final blocked = effectiveKategorialIdentity(
        'u',
        {...account, 'isBlocked': true},
        {'uid': 'u', 'kelompok': 'AMKI'},
      );
      expect(permitsRoomAccess(blocked, 'a', 'AMKI'), isFalse);
      final valid = effectiveKategorialIdentity('u', account, {
        'uid': 'u',
        'kelompok': 'AMKI',
      });
      expect(permitsChurchWrite(valid, 'a', category: 'AMKI'), isTrue);
      expect(permitsRoomAccess(valid, 'other-church', 'AMKI'), isFalse);
    },
  );
}
