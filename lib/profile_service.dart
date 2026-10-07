import 'mobile_notifications.dart';
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'user_manager.dart';
import 'kategorial_config.dart';
import 'profile_support.dart';
import 'upload_support.dart';

class ProfileAccount {
  final String uid;
  final Map<String, dynamic> data;
  ProfileAccount(this.uid, Map<String, dynamic> data) : data = Map.unmodifiable(data);
  String get name => profileText(data['namaLengkap']);
  String get role => profileText(data['role']);
  String get churchId => profileText(data['churchId']);
  String get churchName => profileText(data['churchName']);
  String get jemaatId => profileText(data['jemaatId']);
  String? get photo => profilePhoto(data['photoUrl']);
  bool get linked => profileValidId(jemaatId);
  ProfileAccount withChanges(Map<String, dynamic> changes) => ProfileAccount(uid, {...data, ...changes});
}
class ProfileBook {
  final Map<String, dynamic>? data;
  final String? message;
  const ProfileBook(this.data, {this.message});
}
class ProfileSaved {
  final ProfileAccount account;
  final bool cacheSaved;
  const ProfileSaved(this.account, {this.cacheSaved = true});
}
class ProfileCandidate {
  final String uid, churchId, jemaatId, phone;
  final Map<String, dynamic> data;
  ProfileCandidate({required this.uid, required this.churchId, required this.jemaatId, required this.phone, required Map<String, dynamic> data}) : data = Map.unmodifiable(data);
}
abstract class ProfileGateway {
  String? get signedInUid;
  Stream<String?> get authChanges => const Stream<String?>.empty();
  ProfileAccount? get cachedAccount;
  Future<ProfileAccount> loadAccount();
  Future<ProfileBook> loadBook(ProfileAccount account);
  Future<ProfileSaved> save(ProfileAccount account, String name, {File? photo, bool useBookPhoto = false});
  Future<ProfileCandidate> search(String phone);
  Future<bool> link(ProfileCandidate candidate, String year);
  Future<void> logout();
}
String profileError(Object error) {
  if (error is TimeoutException) return 'Koneksi terlalu lama. Jika sedang menyimpan, hasilnya belum dapat dipastikan. Periksa data terbaru sebelum mengirim ulang.';
  if (error is StateError) return error.message.toString();
  if (error is FirebaseException) {
    if (error.code == 'permission-denied') return 'Akses ditolak. Periksa sesi atau hubungi Admin Gereja.';
    if (error.code == 'not-found') return 'Data akun atau jemaat sudah tidak tersedia. Hubungi Admin Gereja.';
    if (error.code == 'unavailable') return 'Koneksi belum tersedia. Data tersimpan mungkin belum terbaru.';
  }
  return 'Operasi gagal. Periksa koneksi dan coba lagi.';
}

class FirebaseProfileGateway implements ProfileGateway {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final UserManager _manager = UserManager();
  @override String? get signedInUid => _auth.currentUser?.uid;
  @override Stream<String?> get authChanges => _auth.authStateChanges().map((user) => user?.uid);
  void _guard(String uid) {
    if (signedInUid == null || signedInUid != uid) throw StateError('Sesi akun sudah berubah. Silakan masuk ulang.');
  }
  @override ProfileAccount? get cachedAccount {
    final uid = signedInUid;
    if (uid == null || _manager.userId != uid) return null;
    return ProfileAccount(uid, {'namaLengkap': _manager.userNama ?? '', 'photoUrl': _manager.userFotoUrl,
      'role': _manager.userRole ?? 'user', 'churchId': _manager.originalChurchId ?? '',
      'churchName': _manager.originalChurchName ?? '', 'jemaatId': _manager.jemaatId ?? ''});
  }
  Map<String, dynamic> _readData(Map<String, dynamic> data) => {
    for (final entry in data.entries) entry.key: entry.value is Timestamp ? (entry.value as Timestamp).toDate() : entry.value,
  };
  @override Future<ProfileAccount> loadAccount() async {
    final uid = signedInUid;
    if (uid == null) throw StateError('Sesi login berakhir. Silakan masuk ulang.');
    final snapshot = await _db.collection('users').doc(uid).get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));
    _guard(uid);
    if (!snapshot.exists) throw StateError('Dokumen akun tidak ditemukan. Hubungi Admin Gereja.');
    final data = snapshot.data() ?? <String, dynamic>{};
    if (data['isBlocked'] == true) throw StateError('Akun sedang dinonaktifkan. Hubungi Admin Gereja.');
    return ProfileAccount(uid, {...data, if (!data.containsKey('photoUrl') || data['photoUrl'] == null) 'photoUrl': _auth.currentUser?.photoURL});
  }
  @override Future<ProfileBook> loadBook(ProfileAccount account) async {
    _guard(account.uid);
    if (!account.linked) return const ProfileBook(null);
    if (!profileValidId(account.churchId)) return const ProfileBook(null, message: 'Gereja asal akun belum tersedia. Hubungi Admin Gereja.');
    final doc = await _db.collection('churches').doc(account.churchId).collection('jemaat').doc(account.jemaatId)
      .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));
    _guard(account.uid);
    if (!doc.exists) return const ProfileBook(null, message: 'Data jemaat tertaut tidak ditemukan. Hubungi Admin Gereja; tautan tidak diubah otomatis.');
    final data = _readData(doc.data() ?? <String, dynamic>{});
    final owner = profileText(data['uid']);
    if (owner.isNotEmpty && owner != account.uid) return const ProfileBook(null, message: 'Pemilik tautan tidak cocok. Biodata disembunyikan; hubungi Admin Gereja.');
    return ProfileBook(data, message: owner.isEmpty ? 'Data lama: pemilik tautan belum tercatat di buku induk. Minta Admin Gereja memeriksa tautan.' : null);
  }
  @override Future<ProfileSaved> save(ProfileAccount account, String name, {File? photo, bool useBookPhoto = false}) async {
    _guard(account.uid);
    if (name.trim().isEmpty || name.trim().length > 120) throw StateError('Nama wajib diisi, maksimal 120 karakter.');
    // Refresh the account first; cached church/role/link data never authorizes a save.
    final fresh = await loadAccount();
    if (fresh.uid != account.uid) throw StateError('Sesi akun sudah berubah.');
    final changes = profileAccountChanges(name, useBookPhoto: photo == null && useBookPhoto);
    String? uploadedPath;
    try {
      if (photo != null) {
        final suffix = _db.collection('users').doc().id;
        uploadedPath = 'users/${account.uid}/profil_${account.uid}_$suffix.jpg';
        final ref = _storage.ref(uploadedPath);
        final task = ref.putFile(photo, await prepareUpload(photo));
        try { await task.timeout(const Duration(seconds: 60)); }
        on TimeoutException { await task.cancel().timeout(const Duration(seconds: 5), onTimeout: () => false); rethrow; }
        changes['photoUrl'] = await ref.getDownloadURL().timeout(const Duration(seconds: 20));
      }
      _guard(account.uid);
      await _db.collection('users').doc(account.uid).update(changes).timeout(const Duration(seconds: 30));
    } on FirebaseException catch (e) {
      if (uploadedPath != null && ['permission-denied', 'not-found', 'invalid-argument'].contains(e.code)) {
        try { await _storage.ref(uploadedPath).delete().timeout(const Duration(seconds: 10)); } catch (_) {}
      }
      rethrow;
    }
    final result = fresh.withChanges(changes);
    var cached = false;
    if (signedInUid == account.uid && _manager.userId == account.uid) {
      try { await _manager.updateProfil(result.name, result.photo).timeout(const Duration(seconds: 10)); cached = true; } catch (_) {}
    }
    return ProfileSaved(result, cacheSaved: cached);
  }
  @override Future<ProfileCandidate> search(String phone) async {
    final variants = profilePhoneVariants(phone), normalized = profilePhone(phone);
    if (variants.isEmpty || normalized == null) throw StateError('Masukkan nomor HP/WhatsApp yang valid.');
    final account = await loadAccount();
    if (!profileValidId(account.churchId)) throw StateError('Gereja asal akun belum tersedia. Hubungi Admin Gereja.');
    final queries = await Future.wait([
      for (var start = 0; start < variants.length; start += 10)
        _db.collection('churches').doc(account.churchId).collection('jemaat')
          .where('nomorTelepon', whereIn: variants.sublist(start, start + 10 < variants.length ? start + 10 : variants.length))
          .limit(3).get(const GetOptions(source: Source.server)),
    ]).timeout(const Duration(seconds: 20));
    _guard(account.uid);
    final matches = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final query in queries) { for (final doc in query.docs) { matches[doc.id] = doc; } }
    if (matches.isEmpty) throw StateError('Nomor tidak ditemukan di gereja asal akun. Periksa nomor atau hubungi Admin Gereja.');
    if (matches.length != 1) throw StateError('Nomor dipakai lebih dari satu jemaat. Hubungi Admin Gereja untuk memastikan orang yang tepat.');
    final doc = matches.values.single, data = _readData(matches.values.single.data());
    final owner = profileText(data['uid']);
    if (owner.isNotEmpty && owner != account.uid) throw StateError('Data jemaat sudah tertaut ke akun lain. Hubungi Admin Gereja.');
    if (account.linked && account.jemaatId != doc.id) throw StateError('Akun sudah tertaut ke jemaat lain. Hubungi Admin Gereja.');
    return ProfileCandidate(uid: account.uid, churchId: account.churchId, jemaatId: doc.id, phone: normalized, data: data);
  }
  @override Future<bool> link(ProfileCandidate candidate, String year) async {
    _guard(candidate.uid);
    if (!RegExp(r'^\d{4}$').hasMatch(year)) throw StateError('Tahun lahir harus empat digit angka.');
    final userRef = _db.collection('users').doc(candidate.uid);
    final jemaatRef = _db.collection('churches').doc(candidate.churchId).collection('jemaat').doc(candidate.jemaatId);
    final category = await _db.runTransaction<String>((tx) async {
      final user = await tx.get(userRef), jemaat = await tx.get(jemaatRef);
      _guard(candidate.uid);
      if (!user.exists || !jemaat.exists) throw StateError('Data akun atau jemaat sudah tidak tersedia. Cari kembali atau hubungi Admin Gereja.');
      final accountData = user.data()!, jemaatData = _readData(jemaat.data()!);
      validateProfileLink(uid: candidate.uid, churchId: candidate.churchId, jemaatId: candidate.jemaatId,
        phone: candidate.phone, inputYear: year, account: accountData, jemaat: jemaatData);
      final category = KategorialConfig.canonicalJemaat(jemaatData['kelompok']);
      if (accountData['isPengurus'] == true && KategorialConfig.canonicalJemaat(accountData['kelompok']) != category) {
        throw StateError('Kategori pengurus perlu diperiksa Admin Gereja sebelum ditautkan.');
      }
      tx.update(jemaatRef, {'uid': candidate.uid});
      tx.update(userRef, {'jemaatId': candidate.jemaatId, 'kelompok': category});
      return category;
    }).timeout(const Duration(seconds: 30));
    // Local cache failure must not report a committed link as a failed link.
    if (signedInUid != candidate.uid || _manager.userId != candidate.uid || _manager.originalChurchId != candidate.churchId) return false;
    try {
      await _manager.linkJemaatId(candidate.jemaatId).timeout(const Duration(seconds: 10));
      _guard(candidate.uid);
      await _manager.updateKategorialContext(category, pengurus: _manager.isPengurus).timeout(const Duration(seconds: 10));
      return true;
    } catch (_) { return false; }
  }
  @override Future<void> logout() async {
    try { await _auth.signOut().timeout(const Duration(seconds: 20)); }
    catch (_) { if (signedInUid != null) rethrow; }
    try { await Future<void>.sync(MobilePush.logout).timeout(const Duration(seconds: 15)); } catch (_) {}
    await _manager.reset().timeout(const Duration(seconds: 10));
  }
}

