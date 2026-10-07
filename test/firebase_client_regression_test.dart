import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/upload_support.dart';
import '../lib/prayer_feed.dart';
import '../lib/approval_service.dart';
import '../lib/profile_service.dart';
import '../lib/sinkronisasi_jemaat_page.dart';

class PendingGateway extends ProfileGateway {
  @override String? get signedInUid => 'u';
  @override ProfileAccount? get cachedAccount => null;
  @override Future<ProfileAccount> loadAccount() async => ProfileAccount('u', {'churchId': 'a'});
  @override Future<ProfileCandidate> search(String phone) async => ProfileCandidate(uid: 'u', churchId: 'a', jemaatId: 'j', phone: phone, data: {'namaLengkap': 'Nama S.'});
  @override Future<bool> link(ProfileCandidate candidate, String year) async => throw const ApprovalPending('Menunggu persetujuan admin.');
  @override Future<ProfileBook> loadBook(ProfileAccount account) async => const ProfileBook(null);
  @override Future<ProfileSaved> save(ProfileAccount account, String name, {dynamic photo, bool useBookPhoto = false}) => throw UnimplementedError();
  @override Future<void> logout() async {}
}
void main() {
  test('upload uses actual JPEG/PNG/WebP signature, not file extension', () {
    expect(uploadContentType('file.jpg', [137,80,78,71,13,10,26,10], 100), 'image/png');
    expect(uploadContentType('file.txt', [255,216,255], 100), 'image/jpeg');
    expect(uploadContentType('file.jpg', [82,73,70,70,0,0,0,0,87,69,66,80], 100), 'image/webp');
    expect(() => uploadContentType('file.jpg', [60,104,116,109,108], 100), throwsStateError);
  });
  test('photo and attachment limits reject empty and oversized files', () {
    expect(uploadContentType('a.jpg', [255,216,255], maxPhotoBytes), 'image/jpeg');
    expect(() => uploadContentType('a.jpg', [255,216,255], maxPhotoBytes+1), throwsStateError);
    expect(() => uploadContentType('a.pdf', [37,80,68,70,45], maxAttachmentBytes+1, attachment: true), throwsStateError);
    expect(() => uploadContentType('a.jpg', [255,216,255], 0), throwsStateError);
  });
  test('PDF and uppercase Office extensions use compatible MIME types and validate container header', () {
    expect(uploadContentType('a.PDF', [37,80,68,70,45], 100, attachment: true), 'application/pdf');
    expect(uploadContentType('a.DOCX', [80,75,3,4], 100, attachment: true), 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
    expect(uploadContentType('a.xls', [208,207,17,224,161,177,26,225], 100, attachment: true), 'application/vnd.ms-excel');
    expect(() => uploadContentType('a.pdf', [80,75,3,4], 100, attachment: true), throwsStateError);
  });
  test('prayer moderation follows server role, church and block status', () {
    expect(prayerModerator({'role':'admin','churchId':'a'}, 'a'), isTrue);
    expect(prayerModerator({'role':'gembala','churchId':'a'}, 'a'), isTrue);
    expect(prayerModerator({'role':'admin','churchId':'b'}, 'a'), isFalse);
    expect(prayerModerator({'role':'bpj','churchId':'a'}, 'a'), isFalse);
    expect(prayerModerator({'role':'superadmin','isBlocked':true}, 'a'), isFalse);
  });
  testWidgets('pending link returns without claiming success or leaving loading active', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => ElevatedButton(
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SinkronisasiJemaatPage(returnToProfile: true, gateway: PendingGateway()))),
      child: const Text('Open'))))));
    await tester.tap(find.text('Open')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '081234567890');
    await tester.tap(find.text('CARI DATA SAYA')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '2000');
    await tester.tap(find.text('AJUKAN TAUTAN KE ADMIN')); await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Data jemaat berhasil ditautkan.'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
