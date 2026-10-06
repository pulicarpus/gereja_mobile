import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/management_support.dart';
import '../lib/management_service.dart';
import '../lib/daftar_pengguna_page.dart';
import '../lib/detail_pengguna_page.dart';
import '../lib/add_edit_gereja_page.dart';
import '../lib/kelola_gereja_page.dart';

class FakeManagementGateway extends ManagementGateway {
  String? uid = 'actor';
  ManagementAccess actor = const ManagementAccess('actor', 'superadmin', 'A');
  ManagementRecord user = ManagementRecord('target', {'namaLengkap': '', 'email': 123,
    'role': 'user', 'churchId': 'A', 'kelompok': 'AMKI', 'jemaatId': '', 'isPengurus': false});
  ManagementRecord church = ManagementRecord('A', {'nama': 'Gereja Lama', 'daerah': 'Utara', 'alamat': 'Alamat Lama', 'kodeUndangan': 'LAMA123'});
  final auth = StreamController<String?>.broadcast();
  Object? userError, listError, churchError, saveError, enterError, changeError;
  Completer<void>? pendingSave, pendingEnter;
  Completer<ManagementRecord>? pendingLoad;
  int saves = 0, entries = 0, changes = 0, loads = 0;
  String? savedId;
  Map<String, dynamic>? savedValues;
  @override String? get signedInUid => uid;
  @override Stream<String?> get authChanges => auth.stream;
  @override Future<ManagementAccess> access() async => actor;
  @override Stream<List<ManagementRecord>> users() async* {
    if (listError != null) throw listError!;
    yield [user];
  }
  @override Stream<List<ManagementRecord>> churches() async* { yield [church]; }
  @override Future<ManagementRecord> loadUser(String id) async {
    loads++;
    if (userError != null) throw userError!;
    return pendingLoad == null ? user : await pendingLoad!.future;
  }
  @override Future<ManagementRecord> loadChurch(String id) async {
    if (churchError != null) throw churchError!;
    return church;
  }
  @override Future<List<ManagementRecord>> churchChoices() async => [church];
  @override Future<void> changeUser(ManagementRecord expected, String field, dynamic value) async {
    changes++;
    if (changeError != null) throw changeError!;
    user = ManagementRecord(user.id, {...user.data, ...managementUserPatch(actor, user.id, user.data, field, value)});
  }
  @override String newChurchId() => 'new-id';
  @override Future<void> saveChurch(String id, Map<String, dynamic> values, {ManagementRecord? expected}) async {
    saves++; savedId = id; savedValues = values;
    if (pendingSave != null) await pendingSave!.future;
    if (saveError != null) throw saveError!;
    church = ManagementRecord(id, {...church.data, ...values});
  }
  @override Future<void> enterChurch(ManagementRecord church) async {
    entries++;
    if (pendingEnter != null) await pendingEnter!.future;
    if (enterError != null) throw enterError!;
  }
}
Future<void> showPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
}
Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}
void main() {
  const local = ManagementAccess('actor', 'admin', 'A');
  const central = ManagementAccess('actor', 'superadmin', 'A');
  Map<String, dynamic> target({String role = 'user', String church = 'A', String book = ''}) =>
    {'role': role, 'churchId': church, 'jemaatId': book, 'kelompok': 'AMKI', 'isPengurus': true};
  test('Missing church never widens a user query', () {
    expect(managementUserScope(local, 'B'), 'A');
    expect(managementUserScope(central, 'B'), 'B');
    expect(() => managementUserScope(central, null), throwsStateError);
    expect(() => managementUserScope(const ManagementAccess('actor', 'admin', ''), null), throwsStateError);
    expect(() => managementUserScope(central, 'invalid/id'), throwsStateError);
  });
  test('Local administrator cannot modify peers or other churches', () {
    expect(local.canManage(target()), isTrue);
    expect(local.canManage(target(church: 'B')), isFalse);
    expect(local.canManage(target(role: 'admin')), isFalse);
    expect(local.canManage(target(role: 'superadmin')), isFalse);
    expect(const ManagementAccess('actor', 'user', 'A').canManage(target()), isFalse);
  });
  test('Superadmin account and self role changes are protected', () {
    expect(() => managementUserPatch(central, 'target', target(role: 'superadmin'), 'role', 'user'), throwsStateError);
    expect(() => managementUserPatch(local, 'actor', target(), 'role', 'user'), throwsStateError);
    expect(() => managementUserPatch(central, 'actor', target(role: 'admin'), 'role', 'user'), throwsStateError);
  });
  test('Role promotion requires church and resets local leadership', () {
    expect(() => managementUserPatch(central, 'target', target(church: ''), 'role', 'admin'), throwsStateError);
    expect(() => managementUserPatch(local, 'target', target(), 'role', 'superadmin'), throwsStateError);
    expect(managementUserPatch(local, 'target', target(), 'role', 'admin'), {'role': 'admin', 'isPengurus': false});
  });
  test('Linked member is never silently moved to another church', () {
    expect(() => managementUserPatch(central, 'target', target(book: 'book'), 'churchId', 'B'), throwsStateError);
    expect(managementUserPatch(central, 'target', target(book: 'book'), 'churchId', 'A'), isEmpty);
    expect(() => managementUserPatch(local, 'target', target(), 'churchId', 'B'), throwsStateError);
    expect(() => managementUserPatch(central, 'actor', target(), 'churchId', 'B'), throwsStateError);
    expect(managementUserPatch(central, 'target', target(), 'churchId', 'B'), {'churchId': 'B', 'isPengurus': false});
  });
  test('Category changes reset leadership and require a valid category', () {
    expect(managementUserPatch(local, 'target', target(), 'kelompok', 'Perkawan'), {'kelompok': 'Perkawan', 'isPengurus': false});
    expect(() => managementUserPatch(local, 'target', target(), 'kelompok', 'Invalid'), throwsStateError);
  });
  test('Book owner must match before category synchronization', () {
    expect(() => managementCheckBook(null, 'target'), throwsStateError);
    expect(() => managementCheckBook({'uid': ''}, 'target'), throwsStateError);
    expect(() => managementCheckBook({'uid': 'other'}, 'target'), throwsStateError);
    expect(() => managementCheckBook({'uid': 'target'}, 'target'), returnsNormally);
  });
  test('Leadership requires a member in a ministry category', () {
    expect(managementUserPatch(local, 'target', target(), 'isPengurus', false), {'isPengurus': false});
    expect(() => managementUserPatch(central, 'target', target(role: 'admin'), 'isPengurus', true), throwsStateError);
    expect(() => managementUserPatch(local, 'target', {...target(), 'kelompok': 'Lainnya'}, 'isPengurus', true), throwsStateError);
  });
  test('Regional appointment is restricted to Superadmin', () {
    expect(() => managementUserPatch(local, 'target', target(), 'adminDaerahArea', 'Utara'), throwsStateError);
    expect(managementUserPatch(central, 'target', target(), 'adminDaerahArea', ''), {'adminDaerahArea': ''});
  });
  test('Concurrent changes and legacy names are handled safely', () {
    expect(managementUnchanged(target(), {...target(), 'jemaatId': 'new'}, ['churchId', 'jemaatId']), isFalse);
    expect(managementUnchanged(target(), {...target(), 'unrelated': 1}, ['role']), isTrue);
    expect(managementChurchName({'namaGereja': '  ', 'nama': 'Lama'}), 'Lama');
    expect(managementChurchName({'churchName': 'Legacy'}), 'Legacy');
    expect(managementText(123), '123');
    expect(managementUncertain(TimeoutException('pending')), isTrue);
  });
  testWidgets('User list reports read errors and retry works', (tester) async {
    final fake = FakeManagementGateway()..listError = StateError('Pilih gereja terlebih dahulu.');
    await showPage(tester, DaftarPenggunaPage(gateway: fake));
    expect(find.text('Pilih gereja terlebih dahulu.'), findsOneWidget);
    fake.listError = null;
    await tester.tap(find.text('Coba lagi')); await tester.pumpAndSettle();
    expect(find.text('Tanpa Nama'), findsOneWidget);
    await tester.enterText(find.byType(TextField), ' 123 '); await tester.pumpAndSettle();
    expect(find.text('Tanpa Nama'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'absent'); await tester.pumpAndSettle();
    expect(find.text('Nama atau email tidak ditemukan.'), findsOneWidget);
  });
  testWidgets('Empty name and non-string email do not crash detail', (tester) async {
    await showPage(tester, DetailPenggunaPage(userId: 'target', gateway: FakeManagementGateway()));
    expect(find.text('Tanpa Nama'), findsOneWidget);
    expect(find.text('123'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Missing user stops loading and supports reload', (tester) async {
    final fake = FakeManagementGateway()..userError = StateError('Data pengguna tidak ditemukan.');
    await showPage(tester, DetailPenggunaPage(userId: 'target', gateway: fake));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Data pengguna tidak ditemukan.'), findsOneWidget);
    fake.userError = null;
    await tester.tap(find.text('Muat ulang data')); await tester.pumpAndSettle();
    expect(find.text('Tanpa Nama'), findsOneWidget);
  });
  testWidgets('Detail uses current church name rather than stale account name', (tester) async {
    final fake = FakeManagementGateway();
    fake.user = ManagementRecord('target', {...fake.user.data, 'churchName': 'Nama Lama', '_churchDisplayName': 'Nama Terbaru'});
    await showPage(tester, DetailPenggunaPage(userId: 'target', gateway: fake));
    expect(find.text('Gereja: Nama Terbaru'), findsOneWidget);
    expect(find.text('Gereja: Nama Lama'), findsNothing);
  });
  testWidgets('Failed user save disables stale actions until reload', (tester) async {
    final fake = FakeManagementGateway()..changeError = StateError('Data pengguna berubah.');
    await showPage(tester, DetailPenggunaPage(userId: 'target', gateway: fake));
    await reveal(tester, find.text('Jadikan Admin Gereja'));
    await tester.tap(find.text('Jadikan Admin Gereja')); await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan')); await tester.pumpAndSettle();
    expect(fake.changes, 1);
    expect(find.text('Data pengguna berubah.'), findsOneWidget);
    expect(find.text('Jadikan Admin Gereja'), findsNothing);
  });
  testWidgets('Auth change hides loaded account and actions', (tester) async {
    final fake = FakeManagementGateway();
    await showPage(tester, DetailPenggunaPage(userId: 'target', gateway: fake));
    fake.uid = null; fake.auth.add(null); await tester.pumpAndSettle();
    expect(find.text('Sesi berubah. Silakan masuk ulang.'), findsOneWidget);
    expect(find.text('Tanpa Nama'), findsNothing);
  });
  testWidgets('Late user load after disposal is ignored', (tester) async {
    final fake = FakeManagementGateway()..pendingLoad = Completer<ManagementRecord>();
    await tester.pumpWidget(MaterialApp(home: DetailPenggunaPage(userId: 'target', gateway: fake)));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    fake.pendingLoad!.complete(fake.user); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Church editor checks role before enabling save', (tester) async {
    final fake = FakeManagementGateway()..actor = local;
    await showPage(tester, AddEditGerejaPage(gateway: fake));
    expect(find.text('Hanya Superadmin yang dapat mengelola gereja.'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
  });
  testWidgets('Missing church does not become a blank editable form', (tester) async {
    final fake = FakeManagementGateway()..churchError = StateError('Gereja tidak ditemukan.');
    await showPage(tester, AddEditGerejaPage(gerejaId: 'deleted', gateway: fake));
    expect(find.text('Gereja tidak ditemukan.'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
  });
  testWidgets('Church save retains draft and prevents double submit', (tester) async {
    final fake = FakeManagementGateway()..pendingSave = Completer<void>()..saveError = Exception('offline');
    await showPage(tester, AddEditGerejaPage(gateway: fake));
    await tester.enterText(find.byType(TextFormField).at(0), 'Gereja Baru');
    await tester.enterText(find.byType(TextFormField).at(1), 'Utara');
    final nameController = tester.widget<TextFormField>(find.byType(TextFormField).at(0)).controller!;
    final button = find.text('SIMPAN GEREJA');
    await tester.scrollUntilVisible(button, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(button); await tester.pump();
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    expect(fake.saves, 1); expect(fake.savedId, 'new-id');
    fake.pendingSave!.complete(); await tester.pumpAndSettle();
    expect(fake.savedValues!['namaGereja'], 'Gereja Baru');
    expect(nameController.text, 'Gereja Baru');
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  testWidgets('Timeout requires checking data and preserves create ID', (tester) async {
    final fake = FakeManagementGateway()..saveError = TimeoutException('pending');
    await showPage(tester, AddEditGerejaPage(gateway: fake));
    await tester.enterText(find.byType(TextFormField).at(0), 'Gereja Baru');
    await tester.enterText(find.byType(TextFormField).at(1), 'Utara');
    await tester.scrollUntilVisible(find.text('SIMPAN GEREJA'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('SIMPAN GEREJA')); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('SIMPAN GEREJA'), 200, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    fake.churchError = StateError('Gereja tidak ditemukan.'); fake.saveError = Exception('offline');
    await tester.scrollUntilVisible(find.text('Muat ulang data'), -200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Muat ulang data')); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('SIMPAN GEREJA'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('SIMPAN GEREJA')); await tester.pumpAndSettle();
    expect(fake.saves, 2); expect(fake.savedId, 'new-id');
  });
  testWidgets('Context switch is single-flight and reports failure', (tester) async {
    final fake = FakeManagementGateway()..pendingEnter = Completer<void>()..enterError = StateError('Gereja sudah tidak tersedia.');
    await showPage(tester, KelolaGerejaPage(gateway: fake));
    await tester.tap(find.text('Kelola Data')); await tester.pump();
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    expect(fake.entries, 1);
    fake.pendingEnter!.complete(); await tester.pumpAndSettle();
    expect(find.text('Gereja sudah tidak tersedia.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  testWidgets('Returning from church editor refreshes list and preserves invitation', (tester) async {
    final fake = FakeManagementGateway();
    await showPage(tester, KelolaGerejaPage(gateway: fake));
    await tester.tap(find.byTooltip('Edit Info Gereja')); await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byType(TextFormField).at(0)).controller!.text, 'Gereja Lama');
    await tester.enterText(find.byType(TextFormField).at(0), 'Gereja Terbaru');
    await tester.scrollUntilVisible(find.text('SIMPAN GEREJA'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('SIMPAN GEREJA')); await tester.pumpAndSettle();
    expect(find.text('Gereja Terbaru'), findsOneWidget);
    expect(find.text('LAMA123'), findsOneWidget);
    expect(fake.savedValues!.keys.toSet(), {'namaGereja', 'daerah', 'alamat'});
    expect(tester.takeException(), isNull);
  });
}
