import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'management_support.dart';
import 'user_manager.dart';

abstract class ManagementGateway {
  String? get signedInUid;
  Stream<String?> get authChanges => const Stream<String?>.empty();
  Future<ManagementAccess> access();
  Stream<List<ManagementRecord>> users();
  Stream<List<ManagementRecord>> churches();
  Future<ManagementRecord> loadUser(String id);
  Future<ManagementRecord> loadChurch(String id);
  Future<List<ManagementRecord>> churchChoices();
  Future<void> changeUser(ManagementRecord expected, String field, dynamic value);
  String newChurchId();
  Future<void> saveChurch(String id, Map<String, dynamic> values, {ManagementRecord? expected});
  Future<void> enterChurch(ManagementRecord church);
}

class FirebaseManagementGateway implements ManagementGateway {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserManager _manager = UserManager();
  late final String? _uid = signedInUid;
  late final String? _view = _manager.getChurchIdForCurrentView();
  static const _deadline = Duration(seconds: 20);
  static const _server = GetOptions(source: Source.server);
  @override String? get signedInUid => _auth.currentUser?.uid;
  @override Stream<String?> get authChanges => _auth.authStateChanges().map((user) => user?.uid);
  void _guard() {
    if (_uid == null || signedInUid != _uid || _manager.userId != _uid ||
        _view != _manager.getChurchIdForCurrentView()) {
      throw StateError('Sesi atau konteks gereja berubah. Buka ulang halaman ini.');
    }
  }
  ManagementAccess _access(Map<String, dynamic>? data) {
    _guard();
    if (data == null || data['isBlocked'] == true) throw StateError('Akun tidak tersedia atau dinonaktifkan.');
    final actor = ManagementAccess(_uid!, managementText(data['role']), managementText(data['churchId']));
    if (!actor.admin) throw StateError('Halaman ini hanya untuk Admin Gereja atau Superadmin.');
    return actor;
  }
  @override Future<ManagementAccess> access() async {
    _guard();
    return _access((await _db.collection('users').doc(_uid).get(_server).timeout(_deadline)).data());
  }
  String _userScope(ManagementAccess actor) {
    return managementUserScope(actor, _view);
  }
  @override Stream<List<ManagementRecord>> users() async* {
    final actor = await access();
    final scope = _userScope(actor);
    yield* _db.collection('users').where('churchId', isEqualTo: scope).snapshots().asyncMap((snapshot) async {
      final current = await access();
      if (_userScope(current) != scope) throw StateError('Hak akses gereja telah berubah. Buka ulang halaman.');
      return snapshot.docs.map((d) => ManagementRecord(d.id, d.data())).toList();
    });
  }
  void _super(ManagementAccess actor) {
    if (!actor.superAdmin) throw StateError('Hanya Superadmin yang dapat mengelola gereja.');
  }
  @override Stream<List<ManagementRecord>> churches() async* {
    _super(await access());
    yield* _db.collection('churches').snapshots().asyncMap((snapshot) async {
      _super(await access());
      return snapshot.docs.map((d) => ManagementRecord(d.id, d.data())).toList();
    });
  }
  @override Future<ManagementRecord> loadUser(String id) async {
    if (!managementId(id)) throw StateError('ID pengguna tidak valid.');
    final actor = await access();
    final doc = await _db.collection('users').doc(id).get(_server).timeout(_deadline);
    _guard();
    if (!doc.exists) throw StateError('Data pengguna tidak ditemukan.');
    if (!actor.canView(doc.data()!)) throw StateError('Pengguna berada di luar gereja Anda.');
    if (actor.superAdmin && managementText(doc.data()!['churchId']) != _userScope(actor)) {
      throw StateError('Pengguna tidak berada di gereja yang sedang dibuka.');
    }
    final data = doc.data()!;
    final churchId = managementText(data['churchId']);
    String? displayName;
    if (managementId(churchId)) {
      final church = await _db.collection('churches').doc(churchId).get(_server).timeout(_deadline);
      _guard();
      displayName = church.exists ? managementChurchName(church.data()!) : 'Gereja tidak ditemukan';
    }
    // Display-only value: never included in the update patch or written to Firebase.
    return ManagementRecord(id, {...data, if (displayName != null) '_churchDisplayName': displayName});
  }
  @override Future<ManagementRecord> loadChurch(String id) async {
    if (!managementId(id)) throw StateError('ID gereja tidak valid.');
    _super(await access());
    final doc = await _db.collection('churches').doc(id).get(_server).timeout(_deadline);
    _guard();
    if (!doc.exists) throw StateError('Gereja tidak ditemukan.');
    return ManagementRecord(id, doc.data()!);
  }
  @override Future<List<ManagementRecord>> churchChoices() async {
    _super(await access());
    final docs = await _db.collection('churches').get(_server).timeout(_deadline);
    _guard();
    return docs.docs.map((d) => ManagementRecord(d.id, d.data())).toList()
      ..sort((a, b) => managementChurchName(a.data).compareTo(managementChurchName(b.data)));
  }
  @override Future<void> changeUser(ManagementRecord expected, String field, dynamic value) async {
    _guard();
    final actorRef = _db.collection('users').doc(_uid);
    final userRef = _db.collection('users').doc(expected.id);
    await _db.runTransaction((transaction) async {
      final actor = _access((await transaction.get(actorRef)).data());
      final doc = await transaction.get(userRef);
      if (!doc.exists) throw StateError('Data pengguna tidak ditemukan.');
      final data = doc.data()!;
      if (actor.superAdmin && managementText(data['churchId']) != _userScope(actor)) {
        throw StateError('Pengguna sudah berpindah gereja. Muat ulang daftar.');
      }
      if (!managementUnchanged(expected.data, data, ['role', 'churchId', 'jemaatId', 'kelompok', 'isPengurus', 'adminDaerahArea', 'isBlocked'])) {
        throw StateError('Data pengguna berubah. Muat ulang sebelum menyimpan.');
      }
      final patch = managementUserPatch(actor, expected.id, data, field, value);
      DocumentReference<Map<String, dynamic>>? bookRef;
      if (field == 'kelompok' && managementText(data['jemaatId']).isNotEmpty) {
        final church = managementText(data['churchId']), book = managementText(data['jemaatId']);
        if (!managementId(church) || !managementId(book)) throw StateError('Tautan buku induk tidak valid.');
        bookRef = _db.collection('churches').doc(church).collection('jemaat').doc(book);
        final linked = await transaction.get(bookRef);
        managementCheckBook(linked.data(), expected.id);
      }
      if (field == 'churchId' && patch.isNotEmpty) {
        final church = await transaction.get(_db.collection('churches').doc(managementText(value)));
        if (!church.exists) throw StateError('Gereja tujuan sudah tidak tersedia.');
        patch['churchName'] = managementChurchName(church.data()!);
        patch['daerah'] = managementText(church.data()?['daerah']);
      }
      if (field == 'adminDaerahArea' && managementText(value).isNotEmpty) {
        // Choices are verified by the UI; writes still require the current server role.
        if (managementText(value).length > 200) throw StateError('Nama daerah terlalu panjang.');
      }
      _guard();
      if (bookRef != null) transaction.update(bookRef, {'kelompok': patch['kelompok']});
      if (patch.isNotEmpty) transaction.update(userRef, patch);
    }).timeout(_deadline);
    _guard();
    if (expected.id == _uid) {
      // Firebase is authoritative; a local cache failure must not repeat a committed write.
      try {
        if (field == 'kelompok') await _manager.updateKategorialContext(value.toString(), pengurus: false);
        if (field == 'isPengurus') await _manager.updateKategorialContext(_manager.userKomisi ?? 'Umum', pengurus: value == true);
      } catch (_) { /* Refreshed when returning to the main page. */ }
    }
  }
  @override String newChurchId() => _db.collection('churches').doc().id;
  final Map<String, String> _codes = {};
  @override Future<void> saveChurch(String id, Map<String, dynamic> values, {ManagementRecord? expected}) async {
    if (!managementId(id)) throw StateError('ID gereja tidak valid.');
    _super(await access());
    final patch = <String, dynamic>{for (final key in ['namaGereja', 'daerah', 'alamat']) key: managementText(values[key])};
    if (patch['namaGereja'].isEmpty || patch['daerah'].isEmpty) throw StateError('Nama gereja dan daerah wajib diisi.');
    String? code;
    if (expected == null) {
      code = _codes[id];
      if (code == null) {
        const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        final random = Random.secure();
        for (var attempt = 0; attempt < 5; attempt++) {
          final candidate = List.generate(12, (_) => alphabet[random.nextInt(alphabet.length)]).join();
          final duplicates = await _db.collection('churches').where('kodeUndangan', isEqualTo: candidate).limit(1).get(_server).timeout(_deadline);
          if (duplicates.docs.isEmpty) { code = candidate; _codes[id] = candidate; break; }
        }
        if (code == null) throw StateError('Kode undangan belum tersedia. Coba lagi.');
      }
    }
    final ref = _db.collection('churches').doc(id);
    await _db.runTransaction((transaction) async {
      _super(_access((await transaction.get(_db.collection('users').doc(_uid))).data()));
      final doc = await transaction.get(ref);
      _guard();
      if (expected != null) {
        if (!doc.exists) throw StateError('Gereja sudah tidak tersedia.');
        if (!managementUnchanged(expected.data, doc.data()!, ['namaGereja', 'nama', 'churchName', 'daerah', 'alamat', 'lastUpdate'])) {
          throw StateError('Informasi gereja berubah. Muat ulang sebelum menyimpan.');
        }
        transaction.update(ref, {...patch, 'lastUpdate': FieldValue.serverTimestamp()});
      } else if (doc.exists) {
        if (!managementUnchanged(patch, doc.data()!, patch.keys) || doc.data()?['kodeUndangan'] != code) {
          throw StateError('ID gereja telah digunakan. Buka ulang formulir.');
        }
        // A retry after an uncertain result reuses the same document, never duplicates it.
      } else {
        transaction.set(ref, {...patch, 'kodeUndangan': code, 'createdAt': FieldValue.serverTimestamp()});
      }
    }).timeout(_deadline);
  }
  @override Future<void> enterChurch(ManagementRecord church) async {
    final latest = await loadChurch(church.id);
    _guard();
    if (!_manager.isSuperAdmin()) throw StateError('Sesi lokal berubah. Masuk ulang terlebih dahulu.');
    final oldId = _manager.activeChurchId, oldName = _manager.activeChurchName;
    try {
      await _manager.enterChurchContext(latest.id, managementChurchName(latest.data));
      if (signedInUid != _uid || _manager.userId != _uid) throw StateError('Sesi berubah. Silakan masuk ulang.');
    }
    catch (_) {
      if (_manager.userId == _uid && signedInUid == _uid) {
        _manager.activeChurchId = oldId; _manager.activeChurchName = oldName;
        try { await _manager.saveToPrefs(); } catch (_) { /* Preserve the in-memory context. */ }
      }
      rethrow;
    }
  }
}
