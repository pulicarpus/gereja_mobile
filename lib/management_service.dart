import 'kategorial_config.dart';
import 'region_names.dart';
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
  Future<void> changeUser(
    ManagementRecord expected,
    String field,
    dynamic value,
  );
  Future<void> deleteChurch(ManagementRecord expected) =>
      Future.error(StateError('Penghapusan belum tersedia.'));
  Future<void> restoreChurch(ManagementRecord expected) =>
      Future.error(StateError('Pemulihan belum tersedia.'));
  Future<void> renameRegion(String area, String name) =>
      Future.error(StateError('Edit daerah belum tersedia.'));
  Future<void> deleteRegion(String area) =>
      Future.error(StateError('Penghapusan daerah belum tersedia.'));
  String newChurchId();
  Future<void> saveChurch(
    String id,
    Map<String, dynamic> values, {
    ManagementRecord? expected,
  });
  Future<void> enterChurch(ManagementRecord church);
}

class FirebaseManagementGateway implements ManagementGateway {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  FirebaseManagementGateway({FirebaseFirestore? db, FirebaseAuth? auth})
    : _db = db ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;
  final UserManager _manager = UserManager();
  late final String? _uid = signedInUid;
  late final String? _view = _manager.getChurchIdForCurrentView();
  static const _deadline = Duration(seconds: 20);
  static const _server = GetOptions(source: Source.server);
  @override
  String? get signedInUid => _auth.currentUser?.uid;
  @override
  Stream<String?> get authChanges =>
      _auth.authStateChanges().map((user) => user?.uid);
  void _guard() {
    if (_uid == null ||
        signedInUid != _uid ||
        _manager.userId != _uid ||
        _view != _manager.getChurchIdForCurrentView()) {
      throw StateError(
        'Sesi atau konteks gereja berubah. Buka ulang halaman ini.',
      );
    }
  }

  ManagementAccess _access(Map<String, dynamic>? data) {
    _guard();
    if (data == null || data['isBlocked'] == true)
      throw StateError('Akun tidak tersedia atau dinonaktifkan.');
    final actor = ManagementAccess(
      _uid!,
      managementText(data['role']),
      managementText(data['churchId']),
    );
    if (!actor.admin)
      throw StateError('Halaman ini hanya untuk Admin Gereja atau Superadmin.');
    return actor;
  }

  @override
  Future<ManagementAccess> access() async {
    _guard();
    return _access(
      (await _db.collection('users').doc(_uid).get(_server).timeout(_deadline))
          .data(),
    );
  }

  String _userScope(ManagementAccess actor) {
    return managementUserScope(actor, _view);
  }

  @override
  Stream<List<ManagementRecord>> users() async* {
    final actor = await access();
    final scope = _userScope(actor);
    yield* _db
        .collection('users')
        .where('churchId', isEqualTo: scope)
        .snapshots()
        .asyncMap((snapshot) async {
          final current = await access();
          if (_userScope(current) != scope)
            throw StateError(
              'Hak akses gereja telah berubah. Buka ulang halaman.',
            );
          return snapshot.docs
              .map((d) => ManagementRecord(d.id, d.data()))
              .toList();
        });
  }

  void _super(ManagementAccess actor) {
    if (!actor.superAdmin)
      throw StateError('Hanya Superadmin yang dapat mengelola gereja.');
  }

  @override
  Stream<List<ManagementRecord>> churches() async* {
    _super(await access());
    yield* _db.collection('churches').snapshots().asyncMap((snapshot) async {
      _super(await access());
      return snapshot.docs
          .map((d) => ManagementRecord(d.id, d.data()))
          .toList();
    });
  }

  @override
  Future<ManagementRecord> loadUser(String id) async {
    if (!managementId(id)) throw StateError('ID pengguna tidak valid.');
    final actor = await access();
    final doc = await _db
        .collection('users')
        .doc(id)
        .get(_server)
        .timeout(_deadline);
    _guard();
    if (!doc.exists) throw StateError('Data pengguna tidak ditemukan.');
    if (!actor.canView(doc.data()!))
      throw StateError('Pengguna berada di luar gereja Anda.');
    if (actor.superAdmin &&
        managementText(doc.data()!['churchId']) != _userScope(actor)) {
      throw StateError('Pengguna tidak berada di gereja yang sedang dibuka.');
    }
    final data = doc.data()!;
    final churchId = managementText(data['churchId']);
    String? displayName;
    if (managementId(churchId)) {
      final church = await _db
          .collection('churches')
          .doc(churchId)
          .get(_server)
          .timeout(_deadline);
      _guard();
      displayName = church.exists
          ? managementChurchName(church.data()!)
          : 'Gereja tidak ditemukan';
    }
    // Display-only value: never included in the update patch or written to Firebase.
    return ManagementRecord(id, {
      ...data,
      if (displayName != null) '_churchDisplayName': displayName,
    });
  }

  @override
  Future<ManagementRecord> loadChurch(String id) async {
    if (!managementId(id)) throw StateError('ID gereja tidak valid.');
    _super(await access());
    final doc = await _db
        .collection('churches')
        .doc(id)
        .get(_server)
        .timeout(_deadline);
    _guard();
    if (!doc.exists) throw StateError('Gereja tidak ditemukan.');
    return ManagementRecord(id, doc.data()!);
  }

  @override
  Future<List<ManagementRecord>> churchChoices() async {
    _super(await access());
    final docs = await _db
        .collection('churches')
        .get(_server)
        .timeout(_deadline);
    _guard();
    return docs.docs
        .where((d) => d.data()['isArchived'] != true)
        .map((d) => ManagementRecord(d.id, d.data()))
        .toList()
      ..sort(
        (a, b) => managementChurchName(
          a.data,
        ).compareTo(managementChurchName(b.data)),
      );
  }

  @override
  Future<void> changeUser(
    ManagementRecord expected,
    String field,
    dynamic value,
  ) async {
    _guard();
    if (field == 'churchId') {
      await _transfer(
        expected,
        value is ChurchTransferChoice
            ? value
            : ChurchTransferChoice(managementText(value)),
      );
      return;
    }
    final actorRef = _db.collection('users').doc(_uid);
    final userRef = _db.collection('users').doc(expected.id);
    await _db
        .runTransaction((transaction) async {
          final actor = _access((await transaction.get(actorRef)).data());
          final doc = await transaction.get(userRef);
          if (!doc.exists) throw StateError('Data pengguna tidak ditemukan.');
          final data = doc.data()!;
          if (actor.superAdmin &&
              managementText(data['churchId']) != _userScope(actor)) {
            throw StateError(
              'Pengguna sudah berpindah gereja. Muat ulang daftar.',
            );
          }
          if (!managementUnchanged(expected.data, data, [
            'role',
            'churchId',
            'jemaatId',
            'kelompok',
            'isPengurus',
            'adminDaerahArea',
            'isBlocked',
          ])) {
            throw StateError(
              'Data pengguna berubah. Muat ulang sebelum menyimpan.',
            );
          }
          final patch = managementUserPatch(
            actor,
            expected.id,
            data,
            field,
            value,
          );
          DocumentReference<Map<String, dynamic>>? bookRef;
          if (field == 'kelompok' &&
              managementText(data['jemaatId']).isNotEmpty) {
            final church = managementText(data['churchId']),
                book = managementText(data['jemaatId']);
            if (!managementId(church) || !managementId(book))
              throw StateError('Tautan buku induk tidak valid.');
            bookRef = _db
                .collection('churches')
                .doc(church)
                .collection('jemaat')
                .doc(book);
            final linked = await transaction.get(bookRef);
            managementCheckBook(linked.data(), expected.id);
          }
          if (field == 'role' && value == 'gembala') {
            final church = managementText(data['churchId']);
            final member = managementText(data['jemaatId']);
            if (!managementId(church) || !managementId(member))
              throw StateError('Tautan jemaat tidak valid.');
            final linked = await transaction.get(
              _db
                  .collection('churches')
                  .doc(church)
                  .collection('jemaat')
                  .doc(member),
            );
            managementCheckBook(linked.data(), expected.id);
            final churchDoc = await transaction.get(
              _db.collection('churches').doc(church),
            );
            if (!churchDoc.exists ||
                managementText(churchDoc.data()?['daerah']).isEmpty) {
              throw StateError(
                'Gereja atau daerah belum tersedia. Lengkapi data gereja dahulu.',
              );
            }
            patch['daerah'] = managementText(churchDoc.data()?['daerah']);
          }
          if (field == 'adminDaerahArea' && managementText(value).isNotEmpty) {
            // Choices are verified by the UI; writes still require the current server role.
            if (managementText(value).length > 200)
              throw StateError('Nama daerah terlalu panjang.');
          }
          _guard();
          if (bookRef != null)
            transaction.update(bookRef, {'kelompok': patch['kelompok']});
          if (patch.isNotEmpty) transaction.update(userRef, patch);
        })
        .timeout(_deadline);
    _guard();
    if (expected.id == _uid) {
      // Firebase is authoritative; a local cache failure must not repeat a committed write.
      try {
        if (field == 'kelompok')
          await _manager.updateKategorialContext(
            value.toString(),
            pengurus: false,
          );
        if (field == 'isPengurus')
          await _manager.updateKategorialContext(
            _manager.userKomisi ?? 'Umum',
            pengurus: value == true,
          );
      } catch (_) {
        /* Refreshed when returning to the main page. */
      }
    }
  }

  Future<void> _transfer(
    ManagementRecord expected,
    ChurchTransferChoice choice,
  ) async {
    final actor = await access();
    managementUserPatch(
      actor,
      expected.id,
      expected.data,
      'churchId',
      choice.churchId,
    );
    final oldChurch = managementText(expected.data['churchId']);
    if (oldChurch == choice.churchId) return;
    final memberId = managementText(expected.data['jemaatId']);
    if (choice.wholeFamily && !managementId(memberId)) {
      throw StateError(
        'Hubungkan akun ke Data Jemaat sebelum memindahkan keluarga.',
      );
    }
    final source = _db
        .collection('churches')
        .doc(managementId(oldChurch) ? oldChurch : '_unassigned')
        .collection('jemaat');
    final destination = _db
        .collection('churches')
        .doc(choice.churchId)
        .collection('jemaat');
    DocumentSnapshot<Map<String, dynamic>>? headSnapshot;
    String headId = memberId;
    final ids = <String>{};
    if (memberId.isNotEmpty) {
      if (!managementId(oldChurch) || !managementId(memberId)) {
        throw StateError('Tautan jemaat tidak valid.');
      }
      final selected = await source
          .doc(memberId)
          .get(_server)
          .timeout(_deadline);
      managementCheckBook(selected.data(), expected.id);
      headId = managementText(selected.data()?['idKepalaKeluarga'], memberId);
      if (!managementId(headId))
        throw StateError('Tautan keluarga tidak valid.');
      headSnapshot = await source.doc(headId).get(_server).timeout(_deadline);
      if (!headSnapshot.exists)
        throw StateError(
          'Kepala keluarga tidak ditemukan. Perbaiki data keluarga dahulu.',
        );
      final family = await source
          .where('idKepalaKeluarga', isEqualTo: headId)
          .get(_server)
          .timeout(_deadline);
      if (!choice.wholeFamily &&
          memberId == headId &&
          family.docs.any((d) => d.id != headId)) {
        throw StateError(
          'Kepala keluarga masih memiliki anggota. Pilih satu keluarga atau atur kepala keluarga pengganti dahulu.',
        );
      }
      ids.add(memberId);
      if (choice.wholeFamily) {
        ids.add(headId);
        ids.addAll(family.docs.map((d) => d.id));
      }
      if (ids.length > 100)
        throw StateError(
          'Keluarga melebihi 100 orang. Hubungi pengelola sebelum memindahkan.',
        );
    }
    await _db
        .runTransaction((tx) async {
          final currentActor = _access(
            (await tx.get(_db.collection('users').doc(_uid))).data(),
          );
          final userRef = _db.collection('users').doc(expected.id);
          final user = await tx.get(userRef);
          if (!user.exists ||
              !managementUnchanged(expected.data, user.data()!, [
                'churchId',
                'jemaatId',
                'role',
                'isPengurus',
                'adminDaerahArea',
                'kelompok',
                'isBlocked',
              ])) {
            throw StateError('Akun berubah. Muat ulang sebelum memindahkan.');
          }
          if (currentActor.superAdmin &&
              oldChurch != _userScope(currentActor)) {
            throw StateError('Konteks gereja berubah. Buka ulang halaman.');
          }
          final basePatch = managementUserPatch(
            currentActor,
            expected.id,
            user.data()!,
            'churchId',
            choice.churchId,
          );
          final church = await tx.get(
            _db.collection('churches').doc(choice.churchId),
          );
          if (!church.exists || church.data()?['isArchived'] == true)
            throw StateError('Gereja tujuan tidak tersedia.');
          final churchPatch = {
            'churchName': managementChurchName(church.data()!),
            'daerah': managementText(church.data()?['daerah']),
          };
          if (headSnapshot != null) {
            final head = await tx.get(source.doc(headId));
            if (!head.exists ||
                head.data()?['familyRevision'] !=
                    headSnapshot?.data()?['familyRevision']) {
              throw StateError(
                'Susunan keluarga berubah. Muat ulang sebelum memindahkan.',
              );
            }
          }
          final books = <String, Map<String, dynamic>>{};
          final accountPatches = <String, Map<String, dynamic>>{};
          for (final id in ids) {
            final book = await tx.get(source.doc(id));
            final target = await tx.get(destination.doc(id));
            if (!book.exists || target.exists) {
              throw StateError(
                'Data asal hilang atau ID jemaat sudah ada di gereja tujuan. Tidak ada data yang dipindahkan.',
              );
            }
            final data = book.data()!;
            if (managementText(data['idKepalaKeluarga'], id) != headId) {
              throw StateError('Hubungan keluarga berubah. Muat ulang dahulu.');
            }
            final uid = managementText(data['uid']);
            if (id == memberId) managementCheckBook(data, expected.id);
            if (uid.isNotEmpty) {
              if (!managementId(uid) || accountPatches.containsKey(uid)) {
                throw StateError(
                  'Tautan akun keluarga tidak valid atau ganda.',
                );
              }
              final account = await tx.get(_db.collection('users').doc(uid));
              if (!account.exists ||
                  managementText(account.data()?['churchId']) != oldChurch ||
                  managementText(account.data()?['jemaatId']) != id) {
                throw StateError(
                  'Tautan akun dan jemaat tidak cocok. Periksa sinkronisasi keluarga.',
                );
              }
              accountPatches[uid] = {
                ...managementUserPatch(
                  currentActor,
                  uid,
                  account.data()!,
                  'churchId',
                  choice.churchId,
                ),
                ...churchPatch,
                'jemaatId': id,
                'kelompok':
                    data['kelompok'] ?? account.data()?['kelompok'] ?? 'Umum',
              };
            }
            books[id] = transferredMember(data, id, choice.wholeFamily);
          }
          _guard();
          // All reads precede these writes; ownership, account and family move together.
          if (headSnapshot != null && !ids.contains(headId)) {
            tx.update(source.doc(headId), {
              'familyRevision': FieldValue.increment(1),
            });
          }
          for (final entry in books.entries) {
            tx.set(destination.doc(entry.key), entry.value);
            tx.delete(source.doc(entry.key));
          }
          for (final entry in accountPatches.entries) {
            tx.update(_db.collection('users').doc(entry.key), entry.value);
          }
          if (ids.isEmpty) tx.update(userRef, {...basePatch, ...churchPatch});
        })
        .timeout(_deadline);
    _guard();
  }

  @override
  String newChurchId() => _db.collection('churches').doc().id;
  final Map<String, String> _codes = {};
  @override
  Future<void> saveChurch(
    String id,
    Map<String, dynamic> values, {
    ManagementRecord? expected,
  }) async {
    if (!managementId(id)) throw StateError('ID gereja tidak valid.');
    _super(await access());
    final patch = <String, dynamic>{
      for (final key in ['namaGereja', 'daerah', 'alamat'])
        key: managementText(values[key]),
    };
    if (patch['namaGereja'].isEmpty || patch['daerah'].isEmpty)
      throw StateError('Nama gereja dan daerah wajib diisi.');
    final churches = await _db
        .collection('churches')
        .get(_server)
        .timeout(_deadline);
    _guard();
    final activeRecords = churches.docs.map((doc) => doc.data()).toList();
    patch['daerah'] = churchRegionIdentifier(patch['daerah'], activeRecords);
    patch['namaDaerah'] = cleanRegionName(patch['daerah']);
    for (final group in groupChurchRegions(activeRecords)) {
      if (regionNameKey(group.name) == regionNameKey(patch['daerah'])) {
        patch['namaDaerah'] = group.displayName;
      }
    }
    String? code;
    if (expected == null) {
      code = _codes[id];
      if (code == null) {
        const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        final random = Random.secure();
        for (var attempt = 0; attempt < 5; attempt++) {
          final candidate = List.generate(
            12,
            (_) => alphabet[random.nextInt(alphabet.length)],
          ).join();
          final duplicates = await _db
              .collection('churches')
              .where('kodeUndangan', isEqualTo: candidate)
              .limit(1)
              .get(_server)
              .timeout(_deadline);
          if (duplicates.docs.isEmpty) {
            code = candidate;
            _codes[id] = candidate;
            break;
          }
        }
        if (code == null)
          throw StateError('Kode undangan belum tersedia. Coba lagi.');
      }
    }
    final ref = _db.collection('churches').doc(id);
    await _db
        .runTransaction((transaction) async {
          _super(
            _access(
              (await transaction.get(_db.collection('users').doc(_uid))).data(),
            ),
          );
          final doc = await transaction.get(ref);
          _guard();
          if (expected != null) {
            if (!doc.exists || doc.data()?['isArchived'] == true)
              throw StateError('Gereja sudah tidak tersedia.');
            if (!managementUnchanged(expected.data, doc.data()!, [
              'namaGereja',
              'nama',
              'churchName',
              'daerah',
              'alamat',
              'lastUpdate',
            ])) {
              throw StateError(
                'Informasi gereja berubah. Muat ulang sebelum menyimpan.',
              );
            }
            transaction.update(ref, {
              ...patch,
              'lastUpdate': FieldValue.serverTimestamp(),
            });
          } else if (doc.exists) {
            if (!managementUnchanged(patch, doc.data()!, patch.keys) ||
                doc.data()?['kodeUndangan'] != code) {
              throw StateError(
                'ID gereja telah digunakan. Buka ulang formulir.',
              );
            }
            // A retry after an uncertain result reuses the same document, never duplicates it.
          } else {
            transaction.set(ref, {
              ...patch,
              'kodeUndangan': code,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        })
        .timeout(_deadline);
  }

  Future<void> _requireEmptyChurch(ManagementRecord church) async {
    final categories = ['Umum', ...KategorialConfig.pilihanJemaat].toSet();
    final collections = {
      'jemaat',
      'jadwal',
      'pengumuman',
      'transaksi',
      'perpuluhan',
      'aset',
      'gallery',
      'galeri',
      'gallery_folders',
      'settings',
      'bpj_seksi',
      'bpj_penasehat',
      'bpj_bpk',
      'chats',
      for (final category in categories) 'chats_$category',
      for (final category in categories) 'gallery_$category',
      for (final category in categories) 'gallery_folders_$category',
    };
    final refs = _db.collection('churches').doc(church.id);
    final results = await Future.wait([
      _db
          .collection('users')
          .where('churchId', isEqualTo: church.id)
          .limit(1)
          .get(_server),
      _db
          .collection('aset_gereja')
          .where('gerejaId', isEqualTo: church.id)
          .limit(1)
          .get(_server),
      for (final name in collections)
        refs.collection(name).limit(1).get(_server),
    ]).timeout(_deadline);
    _guard();
    if (results.any((result) => result.docs.isNotEmpty) ||
        church.data.entries.any(
          (entry) =>
              entry.key.startsWith('bpj_') &&
              entry.value != null &&
              entry.value.toString() != '' &&
              entry.value.toString() != '{}',
        )) {
      throw StateError(
        'Gereja masih memiliki akun, jemaat, atau riwayat. Pindahkan atau periksa data dahulu; gereja tidak dihapus.',
      );
    }
  }

  Future<void> _archive(List<ManagementRecord> churches, bool archived) async {
    _super(await access());
    if (churches.any(
      (church) => (church.data['isArchived'] == true) == archived,
    )) {
      throw StateError('Status arsip sudah berubah. Muat ulang daftar gereja.');
    }
    if (archived && churches.any((church) => church.id == _view)) {
      throw StateError(
        'Gereja sedang dibuka. Buka gereja lain sebelum menghapusnya.',
      );
    }
    if (churches.length > 400)
      throw StateError('Terlalu banyak gereja untuk satu operasi.');
    if (archived)
      for (final church in churches) await _requireEmptyChurch(church);
    await _db
        .runTransaction((tx) async {
          _super(
            _access((await tx.get(_db.collection('users').doc(_uid))).data()),
          );
          final fresh = <DocumentSnapshot<Map<String, dynamic>>>[];
          for (final church in churches) {
            final doc = await tx.get(_db.collection('churches').doc(church.id));
            if (!doc.exists ||
                !managementUnchanged(church.data, doc.data()!, [
                  'isArchived',
                  'daerah',
                  'namaGereja',
                  'namaDaerah',
                  'lastUpdate',
                  'kodeUndangan',
                ])) {
              throw StateError(
                'Informasi gereja berubah. Muat ulang sebelum melanjutkan.',
              );
            }
            fresh.add(doc);
          }
          _guard();
          for (final doc in fresh) {
            final data = doc.data()!;
            tx.update(doc.reference, {
              'isArchived': archived,
              'lastUpdate': FieldValue.serverTimestamp(),
              if (archived)
                '_archivedInviteCode': data['isArchived'] == true
                    ? data['_archivedInviteCode'] ?? ''
                    : data['kodeUndangan'] ?? '',
              'kodeUndangan': archived
                  ? FieldValue.delete()
                  : data['_archivedInviteCode'] ?? '',
            });
          }
        })
        .timeout(_deadline);
  }

  @override
  Future<void> deleteChurch(ManagementRecord expected) =>
      _archive([expected], true);
  @override
  Future<void> restoreChurch(ManagementRecord expected) =>
      _archive([expected], false);

  @override
  Future<void> renameRegion(String area, String name) async {
    _super(await access());
    final label = cleanRegionName(name);
    if (label.isEmpty || label.length > 200)
      throw StateError('Nama daerah wajib diisi, maksimal 200 karakter.');
    final all = await _db
        .collection('churches')
        .get(_server)
        .timeout(_deadline);
    final groups = groupChurchRegions(all.docs.map((doc) => doc.data()));
    if (groups.any(
      (group) =>
          regionNameKey(group.name) != regionNameKey(area) &&
          (regionNameKey(group.displayName) == regionNameKey(label) ||
              regionNameKey(group.name) == regionNameKey(label)),
    )) {
      throw StateError(
        'Nama tersebut sudah digunakan daerah lain. Gunakan nama berbeda.',
      );
    }
    final matches = all.docs
        .where(
          (doc) =>
              doc.data()['isArchived'] != true &&
              regionNameKey(doc.data()['daerah']) == regionNameKey(area),
        )
        .toList();
    if (matches.isEmpty || matches.length > 400)
      throw StateError(
        'Daerah tidak ditemukan atau terlalu besar untuk satu operasi.',
      );
    await _db
        .runTransaction((tx) async {
          _super(
            _access((await tx.get(_db.collection('users').doc(_uid))).data()),
          );
          final refs = <DocumentReference<Map<String, dynamic>>>[];
          for (final doc in matches) {
            final fresh = await tx.get(doc.reference);
            if (!fresh.exists ||
                fresh.data()?['isArchived'] == true ||
                regionNameKey(fresh.data()?['daerah']) != regionNameKey(area) ||
                !managementUnchanged(doc.data(), fresh.data()!, [
                  'namaDaerah',
                  'lastUpdate',
                ])) {
              throw StateError('Daerah berubah. Muat ulang sebelum menyimpan.');
            }
            refs.add(doc.reference);
          }
          _guard();
          for (final ref in refs)
            tx.update(ref, {
              'namaDaerah': label,
              'lastUpdate': FieldValue.serverTimestamp(),
            });
        })
        .timeout(_deadline);
  }

  @override
  Future<void> deleteRegion(String area) async {
    _super(await access());
    final all = await _db
        .collection('churches')
        .get(_server)
        .timeout(_deadline);
    final matches = all.docs
        .where(
          (doc) =>
              doc.data()['isArchived'] != true &&
              regionNameKey(doc.data()['daerah']) == regionNameKey(area),
        )
        .toList();
    if (matches.isEmpty) throw StateError('Daerah tidak ditemukan.');
    final names = matches
        .map((doc) => doc.data()['daerah']?.toString() ?? '')
        .toSet();
    for (final name in names) {
      final assigned = await _db
          .collection('users')
          .where('adminDaerahArea', isEqualTo: name)
          .limit(1)
          .get(_server)
          .timeout(_deadline);
      if (assigned.docs.isNotEmpty)
        throw StateError(
          'Daerah masih memiliki penugasan admin. Cabut penugasan dahulu.',
        );
      for (final collection in [
        'pengurus_daerah',
        'inventaris_daerah',
        'keuangan_daerah',
        'perpuluhan_daerah',
        'info_surat_daerah',
      ]) {
        final records = await _db
            .collection(collection)
            .where('daerah', isEqualTo: name)
            .limit(1)
            .get(_server)
            .timeout(_deadline);
        if (records.docs.isNotEmpty)
          throw StateError(
            'Daerah masih memiliki pengurus, inventaris, keuangan, atau info/surat. Daerah tidak dihapus.',
          );
      }
      if (name.trim().isEmpty) continue;
      final root = _db
          .collection('struktur_pengurus_daerah')
          .doc(Uri.encodeComponent(name.trim()));
      final structure = await root.get(_server).timeout(_deadline);
      if (structure.exists &&
          structure.data()!.keys.any((key) => key.startsWith('bphd_'))) {
        throw StateError(
          'Daerah masih memiliki pengurus. Daerah tidak dihapus.',
        );
      }
      for (final section in ['penasehat', 'mkdp', 'bpk', 'komisi']) {
        final records = await root
            .collection(section)
            .limit(1)
            .get(_server)
            .timeout(_deadline);
        if (records.docs.isNotEmpty)
          throw StateError(
            'Daerah masih memiliki pengurus. Daerah tidak dihapus.',
          );
      }
      final chat = managementId(name)
          ? await _db
                .collection('chats_daerah')
                .doc(name)
                .get(_server)
                .timeout(_deadline)
          : null;
      if (chat?.exists == true)
        throw StateError(
          'Daerah masih memiliki percakapan. Daerah tidak dihapus.',
        );
    }
    await _archive(
      matches.map((doc) => ManagementRecord(doc.id, doc.data())).toList(),
      true,
    );
  }

  @override
  Future<void> enterChurch(ManagementRecord church) async {
    final latest = await loadChurch(church.id);
    if (latest.data['isArchived'] == true)
      throw StateError('Gereja telah dihapus dari daftar aktif.');
    _guard();
    if (!_manager.isSuperAdmin())
      throw StateError('Sesi lokal berubah. Masuk ulang terlebih dahulu.');
    final oldId = _manager.activeChurchId, oldName = _manager.activeChurchName;
    try {
      await _manager.enterChurchContext(
        latest.id,
        managementChurchName(latest.data),
      );
      if (signedInUid != _uid || _manager.userId != _uid)
        throw StateError('Sesi berubah. Silakan masuk ulang.');
    } catch (_) {
      if (_manager.userId == _uid && signedInUid == _uid) {
        _manager.activeChurchId = oldId;
        _manager.activeChurchName = oldName;
        try {
          await _manager.saveToPrefs();
        } catch (_) {
          /* Preserve the in-memory context. */
        }
      }
      rethrow;
    }
  }
}
