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
    expect(permitsRegionWrite({'role': 'gembala', 'daerah': 'Utara'}, 'Utara', allowPastors: true), isTrue);
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

}
