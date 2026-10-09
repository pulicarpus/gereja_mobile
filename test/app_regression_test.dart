import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/app_safety.dart';
import '../lib/user_manager.dart';
import '../lib/detail_jemaat_page.dart';

void main() {
  test('Read-only legacy parsing accepts numeric and string currency', () {
    expect(legacyAmount(200000), 200000);
    expect(legacyAmount('100000'), 100000);
    expect(legacyAmount('rusak'), isNull);
    expect(legacyAmount(double.nan), isNull);
    expect(legacyText(['Doa', 'Musik']), 'Doa, Musik');
  });
  test('Empty and Unicode initials never index an empty string', () {
    expect(nameInitial('  '), '?');
    expect(nameInitial(null), '?');
    expect(nameInitial('👨‍👩‍👧 Keluarga'), '👨‍👩‍👧');
  });
  for (final role in ['admin', 'superadmin', 'gembala']) {
    test('Registration cannot demote an existing $role', () {
      expect(() => registrationChurchPatch({'role': role}, 'B', 'Baru'), throwsStateError);
    });
  }
  test('Registration cannot clear blocking or account links', () {
    for (final data in [
      {'isBlocked': true}, {'churchId': 'A'}, {'jemaatId': 'J'},
    ]) {
      expect(() => registrationChurchPatch(data, 'B', 'Baru'), throwsStateError);
    }
  });
  test('Unassigned account patch contains only church fields', () {
    final original = {'role': 'user', 'kelompok': 'AMKI', 'photoUrl': 'lama'};
    final patch = registrationChurchPatch(original, 'A', 'Gereja');
    expect(patch, {'churchId': 'A', 'churchName': 'Gereja'});
    expect(original['kelompok'], 'AMKI');
  });
  test('Local admin cannot write another church', () {
    expect(permitsChurchWrite({'role': 'admin', 'churchId': 'A'}, 'B'), isFalse);
    expect(permitsChurchWrite({'role': 'admin', 'churchId': 'A'}, 'A'), isTrue);
  });
  test('Blocked superadmin cannot write', () {
    expect(permitsChurchWrite({'role': 'superadmin', 'isBlocked': true}, 'A'), isFalse);
  });
  test('Category leader must match church and category', () {
    final actor = {'role': 'user', 'churchId': 'A', 'isPengurus': true, 'kelompok': 'AMKI'};
    expect(permitsChurchWrite(actor, 'A', category: 'amki'), isTrue);
    expect(permitsChurchWrite(actor, 'A', category: 'Perkawan'), isFalse);
    expect(permitsChurchWrite(actor, 'B', category: 'AMKI'), isFalse);
    expect(permitsChurchWrite(actor, 'A'), isFalse);
  });
  test('Stale/dangling linked account fails closed', () {
    final book = {'uid': 'owner'};
    expect(() => assertBookOwner(book, null, 'A', 'J'), throwsStateError);
    expect(() => assertBookOwner(book, {'churchId': 'B', 'jemaatId': 'J'}, 'A', 'J'), throwsStateError);
    expect(() => assertBookOwner(book, {'churchId': 'A', 'jemaatId': 'X'}, 'A', 'J'), throwsStateError);
    assertBookOwner(book, {'churchId': 'A', 'jemaatId': 'J'}, 'A', 'J');
  });
  test('Unlinked legacy book remains editable', () {
    assertBookOwner({}, null, 'A', 'J');
  });
  test('Regional posting preserves original separate role policy', () {
    expect(permitsRegionWrite({'role': 'user', 'adminDaerahArea': 'Utara'}, 'Utara'), isTrue);
    expect(permitsRegionWrite({'role': 'admin', 'adminDaerahArea': 'Utara'}, 'Selatan'), isFalse);
    expect(permitsRegionWrite({'role': 'gembala', 'daerah': 'Utara'}, 'Utara'), isFalse);
    expect(permitsRegionWrite({'role': 'gembala', 'daerah': 'Utara'}, 'Utara', allowPastors: true), isFalse);
  });
  test('Linked pastors view their own region without regional edit privileges', () async {
    SharedPreferences.setMockInitialValues({});
    final manager = UserManager();
    await manager.setUser(role: 'gembala', churchId: 'A', churchName: 'Gereja',
      uId: 'pastor', uNama: 'Nama', uJemaatId: 'J', uDaerah: 'Daerah Belitang');
    expect(manager.canViewRegion('Daerah Belitang'), isTrue);
    expect(manager.canViewRegion('Daerah Ketungau'), isFalse);
    expect(manager.canEditRegion('Daerah Belitang'), isFalse);
    await manager.loadFromPrefs();
    expect(manager.canViewRegion('Daerah Belitang'), isTrue);
    manager.jemaatId = null;
    expect(manager.canViewRegion('Daerah Belitang'), isFalse);
    manager.jemaatId = 'J';
    manager.originalChurchId = null;
    expect(manager.canViewRegion('Daerah Belitang'), isFalse);
    manager.originalChurchId = 'A';
    manager.adminDaerahArea = 'Daerah Belitang';
    expect(manager.canEditRegion('Daerah Belitang'), isTrue);
    expect(manager.canEditRegion('Daerah Ketungau'), isFalse);
    await manager.reset();
    expect(manager.canViewRegion('Daerah Belitang'), isFalse);
  });
  test('Revoked regional role falls back to ordinary region immediately and after restart', () async {
    SharedPreferences.setMockInitialValues({});
    final manager = UserManager();
    await manager.setUser(role: 'gembala', churchId: 'A', churchName: 'Gereja',
      uId: 'actor', uNama: 'Nama', uAdminDaerahArea: '  ', uDaerah: ' Utara ');
    expect(manager.daerahForCurrentView, 'Utara');
    expect(manager.isAdminDaerah(), isFalse);
    await manager.loadFromPrefs();
    expect(manager.daerahForCurrentView, 'Utara');
    await manager.reset();
  });
  test('Empty session cache clears stale privileged memory', () async {
    SharedPreferences.setMockInitialValues({});
    final manager = UserManager();
    manager.userRole = 'superadmin'; manager.userId = 'old'; manager.activeChurchId = 'A';
    expect(await manager.loadFromPrefs(), isFalse);
    expect(manager.userId, isNull);
    expect(manager.isAdmin(), isFalse);
    expect(manager.getChurchIdForCurrentView(), isNull);
  });
  testWidgets('Legacy detail fields render without exceptions and empty photo uses fallback', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DetailJemaatPage(jemaatData: {
      'namaLengkap': 123, 'alamat': ['Jalan', 'Gereja'], 'statusKeluarga': 7, 'fotoProfil': '',
    })));
    expect(tester.takeException(), isNull);
    expect(find.text('123'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });
  testWidgets('Shared member detail includes complete fields and birthday action', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DetailJemaatPage(
      showBirthdayGreeting: true,
      jemaatData: {
        'namaLengkap': 'Maria', 'jenisKelamin': 'Wanita',
        'statusBaptis': 'Sudah', 'nomorTelepon': '08123456789',
        'alamat': 'Jalan Gereja', 'kelompok': 'PW',
        'tanggalLahir': '08-10-1990', 'statusKeluarga': 'Istri',
      },
    )));
    for (final value in ['Maria', 'Wanita', 'Sudah', '08123456789', 'Jalan Gereja', 'PW', '08-10-1990', 'Istri']) {
      expect(find.text(value), findsOneWidget);
    }
    expect(find.text('Lihat Anggota Keluarga'), findsOneWidget);
    expect(find.text('Hubungi Jemaat'), findsOneWidget);
    expect(find.text('Ucapkan Selamat Ulang Tahun'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Shared detail formats dates and does not offer contact without a phone', (tester) async {
    await tester.pumpWidget(MaterialApp(home: DetailJemaatPage(
      showBirthdayGreeting: true,
      jemaatData: {'tanggalLahir': DateTime(1990, 10, 8)},
    )));
    expect(find.text('08-10-1990'), findsOneWidget);
    expect(find.text('Hubungi Jemaat'), findsNothing);
    expect(find.text('Ucapkan Selamat Ulang Tahun'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('Annual total includes tithes even on expense-only report', () {
    final balance = annualLedgerBalance([
      {'jenis': 'Pemasukan', 'jumlah': 200000},
      {'jenis': 'Pengeluaran', 'jumlah': '50000'},
    ], [{'jumlah': '100000'}]);
    expect(balance.total, 250000);
    expect(balance.invalidRows, 0);
  });
  test('Category balances do not import general tithes', () {
    final balance = annualLedgerBalance([
      {'jenis': 'Pemasukan', 'jumlah': 200000, 'kategori': 'AMKI'},
      {'jenis': 'Pengeluaran', 'jumlah': 50000, 'kategori': 'AMKI'},
      {'jenis': 'Pemasukan', 'jumlah': 999999, 'kategori': 'Umum'},
    ], [{'jumlah': 100000}], category: 'AMKI');
    expect(balance.total, 150000);
  });
  test('Unparseable amounts and types are reported, not silently accepted as zero', () {
    final balance = annualLedgerBalance([
      {'jenis': 'Pemasukan', 'jumlah': 'rusak'},
      {'jenis': 'Lain', 'jumlah': 50000},
    ], [{'jumlah': null}]);
    expect(balance.total, 0);
    expect(balance.invalidRows, 3);
  });
  test('Region permission rejects blocked and wrong-region pastors', () {
    expect(permitsRegionWrite({'role': 'superadmin', 'isBlocked': true}, 'Utara'), isFalse);
    expect(permitsRegionWrite({'role': 'bpj', 'daerah': 'Selatan'}, 'Utara', allowPastors: true), isFalse);
  });

  test('Room access uses fresh church/category without granting moderation', () {
    final actor = {'role': 'user', 'churchId': 'A', 'kelompok': 'AMKI'};
    expect(permitsRoomAccess(actor, 'A', 'AMKI'), isTrue);
    expect(permitsChurchWrite(actor, 'A', category: 'AMKI'), isFalse);
    expect(permitsRoomAccess(actor, 'B', null), isFalse);
    expect(permitsRoomAccess(actor, 'A', 'Perkaria'), isFalse);
    expect(permitsRoomAccess({...actor, 'isBlocked': true}, 'A', null), isFalse);
  });

  test('Global song admin rights do not require an active church', () {
    expect(permitsGlobalSongWrite({'role': 'superadmin'}), isTrue);
    expect(permitsGlobalSongWrite({'role': 'admin'}), isTrue);
    expect(permitsGlobalSongWrite({'role': 'user', 'isPengurus': true}), isFalse);
    expect(permitsGlobalSongWrite({'role': 'superadmin', 'isBlocked': true}), isFalse);
  });

  test('Retry with same payload acknowledges an already committed create', () {
    assertRetryMatches({'nominal': 100000, 'nama': 'Gereja', 'extra': 'lama'},
      {'nominal': 100000, 'nama': 'Gereja'});
  });
  test('Edited retry draft cannot be reported saved against the original create', () {
    expect(() => assertRetryMatches({'nominal': 100000}, {'nominal': 200000}), throwsStateError);
    expect(() => assertRetryMatches({'judul': 'Awal'}, {'judul': 'Revisi'}), throwsStateError);
  });

}
