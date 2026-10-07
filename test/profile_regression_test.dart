import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/profile_support.dart';
import '../lib/profile_service.dart';
import '../lib/profil_page.dart';
import '../lib/sinkronisasi_jemaat_page.dart';

class FakeProfileGateway extends ProfileGateway {
  String? uid = 'u';
  ProfileAccount account = ProfileAccount('u', {'namaLengkap': 'Nama Lama', 'photoUrl': '', 'role': 'user', 'churchId': 'A', 'churchName': 'Gereja Asal', 'jemaatId': ''});
  ProfileBook book = ProfileBook({'namaLengkap': 'Nama Resmi', 'tanggalLahir': DateTime(2000, 1, 1), 'nomorTelepon': 81234567890, 'karuniaPelayanan': ['Musik', 'Mengajar']});
  Future<ProfileAccount> Function()? loading;
  Future<ProfileSaved> Function(ProfileAccount, String)? saving;
  Future<void> Function()? loggingOut;
  Future<ProfileCandidate> Function()? searching;
  Future<bool> Function()? linking;
  final StreamController<String?> auth = StreamController<String?>.broadcast();
  int loads = 0, saves = 0, links = 0, searches = 0;
  @override String? get signedInUid => uid;
  @override Stream<String?> get authChanges => auth.stream;
  @override ProfileAccount? get cachedAccount => uid == account.uid ? account : null;
  @override Future<ProfileAccount> loadAccount() async { loads++; return loading == null ? account : await loading!(); }
  @override Future<ProfileBook> loadBook(ProfileAccount account) async => book;
  @override Future<ProfileSaved> save(ProfileAccount original, String name, {File? photo, bool useBookPhoto = false}) async {
    saves++;
    if (saving != null) return saving!(original, name);
    account = original.withChanges({'namaLengkap': name});
    return ProfileSaved(account);
  }
  @override Future<ProfileCandidate> search(String phone) async {
    searches++;
    if (searching != null) return searching!();
    return ProfileCandidate(uid: 'u', churchId: 'A', jemaatId: 'j', phone: '081234567890', data: {'namaLengkap': 'Nama Resmi', 'tanggalLahir': '01-01-2000'});
  }
  @override Future<bool> link(ProfileCandidate candidate, String year) async {
    links++;
    if (linking != null) return linking!();
    if (year != '2000') throw StateError('Tahun tidak cocok');
    account = account.withChanges({'jemaatId': 'j'});
    return true;
  }
  @override Future<void> logout() async { if (loggingOut != null) await loggingOut!(); uid = null; }
}
void main() {
  test('Year verification rejects substrings and invalid calendar dates', () {
    expect(profileVerifyYear('01-01-2000', '2000'), isTrue);
    for (final invalid in ['01-0', '01-2', '0000', '200', 'abcd', '2001']) {
      expect(profileVerifyYear('01-01-2000', invalid), isFalse);
    }
    expect(profileBirthYear('31-02-2000'), isNull);
    expect(profileBirthYear('29-02-2000'), 2000);
    expect(profileBirthYear('29-02-2001'), isNull);
    expect(profileBirthYear(DateTime(1985, 2, 3)), 1985);
    expect(profileBirthYear('1985'), 1985);
    expect(profileDateText(DateTime(1985, 2, 3)), '03-02-1985');
    expect(profileDateText('1985-02-03T00:00:00Z'), '03-02-1985');
  });
  test('Phone formats and legacy numeric fields use the same normalized identity', () {
    expect(profilePhone('+62 (812) 3456.7890'), '081234567890');
    expect(profilePhone('0812-3456-7890'), '081234567890');
    expect(profilePhone(profileText(81234567890)), '081234567890');
    expect(profilePhoneVariants('+6281234567890'), containsAll(['081234567890', '6281234567890', 81234567890]));
    expect(profilePhoneVariants('bad'), isEmpty);
    expect(profilePhone('++6281234567890'), isNull);
    expect(profilePhone('+852 9999 9999'), '85299999999');
    expect(profilePhone('123'), isNull);
    expect(profileText(['Musik', 'Mengajar']), 'Musik, Mengajar');
  });
  test('Custom photo priority handles legacy and unique uploads without another account match', () {
    const old = 'https://firebasestorage.googleapis.com/v0/b/b/o/users%2Fu%2Fprofil_u.jpg?alt=media';
    const fresh = 'https://firebasestorage.googleapis.com/v0/b/b/o/users%2Fu%2Fprofil_u_unique.jpg';
    const book = 'https://example.com/book.jpg';
    expect(profileCustomPhoto(old, 'u'), isTrue);
    expect(profileCustomPhoto(fresh, 'u'), isTrue);
    expect(profileCustomPhoto(fresh, 'other'), isFalse);
    expect(profileDisplayPhoto(uid: 'u', accountPhoto: old, bookPhoto: book), old);
    expect(profileDisplayPhoto(uid: 'u', accountPhoto: 'https://example.com/google.jpg', bookPhoto: book), book);
    expect(profilePhoto('javascript:alert(1)'), isNull);
    expect(profilePhoto(''), isNull);
  });
  test('Name-only save does not overwrite a photo and book photo reset stays legacy-compatible', () {
    expect(profileAccountChanges(' Nama '), {'namaLengkap': 'Nama'});
    expect(profileAccountChanges('Nama', useBookPhoto: true), {'namaLengkap': 'Nama', 'photoUrl': null});
  });
  test('Fresh ownership rejects a racing claim, changed church, phone and existing link', () {
    final account = <String, dynamic>{'churchId': 'A', 'jemaatId': ''};
    final book = <String, dynamic>{'uid': '', 'nomorTelepon': '081234567890', 'tanggalLahir': '01-01-2000'};
    void verify(Map<String, dynamic> a, Map<String, dynamic> b) => validateProfileLink(uid: 'u', churchId: 'A', jemaatId: 'j', phone: '081234567890', inputYear: '2000', account: a, jemaat: b);
    verify(account, book);
    expect(() => verify(account, {...book, 'uid': 'other'}), throwsStateError);
    expect(() => verify({...account, 'churchId': 'B'}, book), throwsStateError);
    expect(() => verify({...account, 'jemaatId': 'another'}, book), throwsStateError);
    expect(() => verify({...account, 'isBlocked': true}, book), throwsStateError);
    expect(() => verify(account, {...book, 'nomorTelepon': '081299999999'}), throwsStateError);
    expect(() => verify(account, {...book, 'tanggalLahir': '31-02-2000'}), throwsStateError);
    verify({...account, 'jemaatId': 'j'}, {...book, 'uid': 'u'});
    expect(account['jemaatId'], ''); expect(book['uid'], '');
  });
  Future<void> openProfile(WidgetTester tester, FakeProfileGateway gateway) async {
    await tester.pumpWidget(MaterialApp(routes: {'/login': (_) => const Scaffold(body: Text('LOGIN'))}, home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ProfilPage(gateway: gateway))), child: const Text('BUKA'))))));
    await tester.tap(find.text('BUKA')); await tester.pumpAndSettle();
  }
  Future<void> reveal(WidgetTester tester, Finder target, {double delta = 200}) async {
    await tester.scrollUntilVisible(target, delta, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
  }
  testWidgets('Missing authentication shows login action without loading or remote requests', (tester) async {
    final gateway = FakeProfileGateway()..uid = null;
    await openProfile(tester, gateway);
    expect(find.textContaining('Sesi login berakhir'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(gateway.loads, 0); expect(gateway.saves, 0);
    await tester.tap(find.text('Masuk ulang')); await tester.pumpAndSettle();
    expect(find.text('LOGIN'), findsOneWidget);
  });
  testWidgets('Typed legacy book data displays without casting failures', (tester) async {
    final gateway = FakeProfileGateway(); gateway.account = gateway.account.withChanges({'jemaatId': 'j'});
    await openProfile(tester, gateway);
    expect(find.text('Nama Resmi'), findsOneWidget);
    expect(find.text('01-01-2000'), findsOneWidget);
    expect(find.text('81234567890'), findsOneWidget);
    expect(find.text('Musik, Mengajar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Account load failure clears loading and offers retry', (tester) async {
    final gateway = FakeProfileGateway()..loading = () async => throw StateError('Koneksi gagal');
    await openProfile(tester, gateway);
    expect(find.text('Koneksi gagal'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    gateway.loading = null;
    await tester.tap(find.text('Coba lagi')); await tester.pumpAndSettle();
    expect(find.text('Koneksi gagal'), findsNothing); expect(gateway.loads, 2);
  });
  testWidgets('Refresh preserves unsaved name and does not save remotely', (tester) async {
    final gateway = FakeProfileGateway(); await openProfile(tester, gateway);
    await tester.enterText(find.byType(TextField), 'Nama Belum Disimpan'); await tester.pump();
    await tester.tap(find.byTooltip('Muat ulang profil')); await tester.pumpAndSettle();
    expect(find.text('Nama Belum Disimpan'), findsOneWidget); expect(gateway.saves, 0);
  });
  testWidgets('Pending save disables repeat submission and preserves input after failure', (tester) async {
    final gateway = FakeProfileGateway(); final pending = Completer<ProfileSaved>();
    gateway.saving = (_, __) => pending.future;
    await openProfile(tester, gateway);
    await tester.enterText(find.byType(TextField), 'Nama Baru');
    await reveal(tester, find.text('SIMPAN NAMA & FOTO'));
    await tester.tap(find.text('SIMPAN NAMA & FOTO')); await tester.pump();
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'SIMPAN NAMA & FOTO')).onPressed, isNull);
    expect(gateway.saves, 1);
    pending.completeError(StateError('Simpan ditolak')); await tester.pumpAndSettle();
    await reveal(tester, find.text('Simpan ditolak'), delta: -200);
    expect(find.text('Simpan ditolak'), findsOneWidget);
    await reveal(tester, find.text('Nama Baru'));
    expect(find.text('Nama Baru'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  testWidgets('Uncertain save cannot be blindly repeated', (tester) async {
    final gateway = FakeProfileGateway()..saving = (_, __) async => throw TimeoutException('uncertain');
    await openProfile(tester, gateway);
    await reveal(tester, find.text('SIMPAN NAMA & FOTO')); await tester.tap(find.text('SIMPAN NAMA & FOTO')); await tester.pumpAndSettle();
    await reveal(tester, find.text('SIMPAN NAMA & FOTO'));
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'SIMPAN NAMA & FOTO')).onPressed, isNull);
    await reveal(tester, find.textContaining('Pengiriman ulang dinonaktifkan'), delta: -200);
    expect(find.textContaining('Pengiriman ulang dinonaktifkan'), findsOneWidget);
  });
  testWidgets('Cancellation of linking returns to existing profile and refreshes account', (tester) async {
    final gateway = FakeProfileGateway(); await openProfile(tester, gateway); final loads = gateway.loads;
    await tester.tap(find.text('HUBUNGKAN DATA JEMAAT')); await tester.pumpAndSettle();
    await reveal(tester, find.text('Kembali ke Profil')); await tester.tap(find.text('Kembali ke Profil')); await tester.pumpAndSettle();
    expect(find.text('Profil Saya'), findsOneWidget); expect(gateway.loads, loads + 1); expect(gateway.links, 0);
  });
  testWidgets('Successful linking returns to profile with refreshed book without resetting navigation', (tester) async {
    final gateway = FakeProfileGateway(); await openProfile(tester, gateway);
    await tester.tap(find.text('HUBUNGKAN DATA JEMAAT')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '+62 (812) 3456.7890');
    await tester.tap(find.text('CARI DATA SAYA')); await tester.pumpAndSettle();
    expect(find.text('Nama Resmi'), findsNothing); expect(find.text('Nama R.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '2000');
    await tester.tap(find.text('AJUKAN TAUTAN KE ADMIN')); await tester.pumpAndSettle();
    expect(find.text('Profil Saya'), findsOneWidget); expect(find.text('Nama Resmi'), findsOneWidget);
    expect(find.text('BUKA'), findsNothing); expect(gateway.links, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Disposed profile ignores late account response', (tester) async {
    final pending = Completer<ProfileAccount>(), gateway = FakeProfileGateway(); gateway.loading = () => pending.future;
    await tester.pumpWidget(MaterialApp(home: ProfilPage(gateway: gateway))); await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(gateway.account); await tester.pumpAndSettle(); expect(tester.takeException(), isNull);
  });
  testWidgets('Changing authentication discards prior account and pending results', (tester) async {
    final gateway = FakeProfileGateway(); await openProfile(tester, gateway);
    gateway.uid = 'another'; gateway.auth.add('another'); await tester.pumpAndSettle();
    expect(find.textContaining('Sesi login berakhir'), findsOneWidget);
    expect(find.text('Nama Lama'), findsNothing);
    expect(find.text('SIMPAN NAMA & FOTO'), findsNothing);
  });
  testWidgets('Expired session disables jemaat search', (tester) async {
    final gateway = FakeProfileGateway()..uid = null;
    await tester.pumpWidget(MaterialApp(home: SinkronisasiJemaatPage(gateway: gateway, returnToProfile: true))); await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'CARI DATA SAYA')).onPressed, isNull);
    expect(find.byType(LinearProgressIndicator), findsNothing); expect(gateway.searches, 0);
  });
  testWidgets('Disposed search ignores a delayed lookup result', (tester) async {
    final gateway = FakeProfileGateway(); final pending = Completer<ProfileCandidate>(); gateway.searching = () => pending.future;
    await tester.pumpWidget(MaterialApp(home: SinkronisasiJemaatPage(gateway: gateway, returnToProfile: true))); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '081234567890');
    await tester.tap(find.text('CARI DATA SAYA')); await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(ProfileCandidate(uid: 'u', churchId: 'A', jemaatId: 'j', phone: '081234567890', data: {'namaLengkap': 'Nama'}));
    await tester.pumpAndSettle(); expect(tester.takeException(), isNull);
  });
  testWidgets('A pending link locks search reset and profile-return controls', (tester) async {
    final gateway = FakeProfileGateway(); final pending = Completer<bool>(); gateway.linking = () => pending.future;
    await tester.pumpWidget(MaterialApp(home: SinkronisasiJemaatPage(gateway: gateway, returnToProfile: true))); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '081234567890'); await tester.tap(find.text('CARI DATA SAYA')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2000'); await tester.tap(find.text('AJUKAN TAUTAN KE ADMIN')); await tester.pump();
    await reveal(tester, find.text('Kembali ke Profil'));
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Bukan data saya, cari ulang')).onPressed, isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Kembali ke Profil')).onPressed, isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox())); pending.completeError(StateError('Gagal'));
    await tester.pumpAndSettle(); expect(tester.takeException(), isNull);
  });
  testWidgets('Failed logout preserves the session and unlocks the page', (tester) async {
    final gateway = FakeProfileGateway(); final pending = Completer<void>(); gateway.loggingOut = () => pending.future;
    await openProfile(tester, gateway); await reveal(tester, find.text('Keluar dari akun')); await tester.tap(find.text('Keluar dari akun'));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Ya, keluar')); await tester.pump();
    pending.completeError(StateError('Logout ditolak')); await tester.pumpAndSettle();
    await reveal(tester, find.text('Logout ditolak'), delta: -200);
    expect(gateway.uid, 'u'); expect(find.text('Logout ditolak'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

}
