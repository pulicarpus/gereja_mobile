import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:characters/characters.dart';
import 'user_manager.dart';
import 'kategorial_config.dart';

String legacyText(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is Iterable) return value.map((e) => e.toString()).join(', ');
  return value.toString();
}

String nameInitial(Object? value) {
  final name = legacyText(value).trim();
  return name.isEmpty ? '?' : name.characters.first.toUpperCase();
}

int? legacyAmount(Object? value) {
  if (value is num) return value.isFinite ? value.toInt() : null;
  return int.tryParse(legacyText(value).trim());
}

bool permitsChurchWrite(Map<String, dynamic> actor, String churchId,
    {String? category}) {
  if (actor['isBlocked'] == true || churchId.trim().isEmpty) return false;
  if (actor['role'] == 'superadmin') return true;
  if (actor['churchId']?.toString().trim() != churchId.trim()) return false;
  if (actor['role'] == 'admin') return true;
  return category != null && category.trim().isNotEmpty &&
      actor['isPengurus'] == true &&
      KategorialConfig.same(actor['kelompok'], category);
}

void assertBookOwner(Map<String, dynamic> book, Map<String, dynamic>? account,
    String churchId, String jemaatId) {
  final uid = legacyText(book['uid']).trim();
  if (uid.isEmpty) return;
  if (account == null || legacyText(account['churchId']).trim() != churchId ||
      legacyText(account['jemaatId']).trim() != jemaatId) {
    throw StateError('Tautan akun dan buku induk berubah. Muat ulang dahulu.');
  }
}

/// Captures UI scope before asynchronous work. This only reads existing fields.
class ChurchWriteAccess {
  final String uid;
  final String churchId;
  final String? category;
  ChurchWriteAccess._(this.uid, this.churchId, this.category);

  static Future<ChurchWriteAccess> check(String churchId, {String? category}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sesi login berakhir.');
    final access = ChurchWriteAccess._(uid, churchId, category);
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid)
        .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));
    access.assertCurrent();
    if (!doc.exists || !permitsChurchWrite(doc.data()!, churchId, category: category)) {
      throw StateError('Anda tidak memiliki izin menyimpan data ini.');
    }
    return access;
  }

  void assertCurrent() {
    if (FirebaseAuth.instance.currentUser?.uid != uid ||
        UserManager().userId != uid ||
        UserManager().getChurchIdForCurrentView() != churchId) {
      throw StateError('Sesi atau gereja aktif berubah. Buka ulang halaman.');
    }
  }

  Future<void> inTransaction(Transaction tx) async {
    final actor = await tx.get(FirebaseFirestore.instance.collection('users').doc(uid));
    assertCurrent();
    if (!actor.exists || !permitsChurchWrite(actor.data()!, churchId, category: category)) {
      throw StateError('Izin Anda sudah berubah.');
    }
  }
}

Future<void> changeJemaatStatus(String churchId, String jemaatId, String? status) async {
  final access = await ChurchWriteAccess.check(churchId);
  final db = FirebaseFirestore.instance;
  await db.runTransaction((tx) async {
    await access.inTransaction(tx);
    final ref = db.collection('churches').doc(churchId).collection('jemaat').doc(jemaatId);
    final book = await tx.get(ref);
    if (!book.exists) throw StateError('Data jemaat sudah dihapus.');
    access.assertCurrent();
    tx.update(ref, {'status': status});
  }).timeout(const Duration(seconds: 20));
}

Future<void> deleteUnlinkedJemaat(String churchId, String jemaatId) async {
  final access = await ChurchWriteAccess.check(churchId);
  final db = FirebaseFirestore.instance;
  final links = await db.collection('users').where('churchId', isEqualTo: churchId)
      .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));
  if (links.docs.any((d) => legacyText(d.data()['jemaatId']).trim() == jemaatId)) {
    throw StateError('Jemaat masih tertaut ke akun. Lepaskan tautan melalui menu profil terlebih dahulu.');
  }
  final col = db.collection('churches').doc(churchId).collection('jemaat');
  final dependents = await col.where('idKepalaKeluarga', isEqualTo: jemaatId)
      .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));
  if (dependents.docs.any((d) => d.id != jemaatId)) {
    throw StateError('Masih ada anggota keluarga yang merujuk jemaat ini. Atur keluarga dahulu.');
  }
  await db.runTransaction((tx) async {
    await access.inTransaction(tx);
    final ref = col.doc(jemaatId);
    final book = await tx.get(ref);
    if (!book.exists) return;
    final data = book.data()!;
    if (legacyText(data['uid']).trim().isNotEmpty ||
        data['statusKeluarga'] == 'Kepala Keluarga' ||
        data['idKepalaKeluarga'] == jemaatId) {
      throw StateError('Akun atau kepala keluarga harus diselesaikan dahulu. Data tidak dihapus.');
    }
    access.assertCurrent();
    tx.delete(ref);
  }).timeout(const Duration(seconds: 20));
}

Map<String, dynamic> registrationChurchPatch(Map<String, dynamic> account,
    String churchId, String churchName) {
  if (account['isBlocked'] == true ||
      (account['role']?.toString() ?? 'user') != 'user' ||
      legacyText(account['jemaatId']).trim().isNotEmpty ||
      legacyText(account['churchId']).trim().isNotEmpty) {
    throw StateError('Akun sudah terdaftar atau tidak dapat diubah di sini. Masuk kembali.');
  }
  return {'churchId': churchId, 'churchName': churchName};
}

bool permitsRegionWrite(Map<String, dynamic> actor, String area,
    {bool allowPastors = false}) {
  if (actor['isBlocked'] == true || area.trim().isEmpty) return false;
  if (actor['role'] == 'superadmin') return true;
  if (legacyText(actor['adminDaerahArea']).trim() == area.trim()) return true;
  return allowPastors && (actor['role'] == 'gembala' || actor['role'] == 'bpj') &&
      legacyText(actor['daerah']).trim() == area.trim();
}

Future<String> checkRegionWrite(String area, {bool allowPastors = false}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw StateError('Sesi login berakhir.');
  final actor = await FirebaseFirestore.instance.collection('users').doc(uid)
      .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));
  if (FirebaseAuth.instance.currentUser?.uid != uid || UserManager().userId != uid ||
      !actor.exists || !permitsRegionWrite(actor.data()!, area, allowPastors: allowPastors)) {
    throw StateError('Sesi atau izin daerah sudah berubah.');
  }
  return uid;
}

class LedgerBalance {
  final int total;
  final int invalidRows;
  const LedgerBalance(this.total, this.invalidRows);
}

/// Annual balance deliberately has no monthly list/type filter.
LedgerBalance annualLedgerBalance(Iterable<Map<String, dynamic>> transactions,
    Iterable<Map<String, dynamic>> tithes, {String? category}) {
  final general = category == null || category.trim().isEmpty;
  int total = 0, invalid = 0;
  for (final data in transactions) {
    final group = legacyText(data['kategori']).trim();
    if (general ? (group.isNotEmpty && group.toLowerCase() != 'umum') : !KategorialConfig.same(group, category)) continue;
    final amount = legacyAmount(data['jumlah']);
    if (amount == null || (data['jenis'] != 'Pemasukan' && data['jenis'] != 'Pengeluaran')) {
      invalid++;
      continue;
    }
    total += data['jenis'] == 'Pemasukan' ? amount : -amount;
  }
  if (general) {
    for (final data in tithes) {
      final amount = legacyAmount(data['jumlah']);
      if (amount == null) { invalid++; } else { total += amount; }
    }
  }
  return LedgerBalance(total, invalid);
}

/// Retains the existing regional collections and fields; no backfill/migration.
Future<void> saveRegionChanges(String area,
    Map<DocumentReference, Map<String, dynamic>?> changes,
    {bool createOnly = false, bool requireExisting = false}) async {
  final uid = await checkRegionWrite(area, allowPastors: true);
  final db = FirebaseFirestore.instance;
  await db.runTransaction((tx) async {
    final actor = await tx.get(db.collection('users').doc(uid));
    final current = <DocumentReference, DocumentSnapshot>{};
    for (final ref in changes.keys) {
      current[ref] = await tx.get(ref);
    }
    if (FirebaseAuth.instance.currentUser?.uid != uid || UserManager().userId != uid ||
        !actor.exists || !permitsRegionWrite(actor.data()!, area, allowPastors: true)) {
      throw StateError('Sesi atau izin daerah berubah.');
    }
    for (final entry in changes.entries) {
      final fresh = current[entry.key]!;
      final raw = fresh.data();
      final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      if (fresh.exists && legacyText(data['daerah']).trim() != area.trim()) {
        throw StateError('Transaksi bukan milik daerah ini atau daerahnya belum dapat dipastikan.');
      }
      if (requireExisting && !fresh.exists && entry.value != null) {
        throw StateError('Transaksi telah dihapus. Muat ulang dahulu.');
      }
    }
    for (final entry in changes.entries) {
      final fresh = current[entry.key]!;
      if (entry.value == null) {
        if (fresh.exists) tx.delete(entry.key);
      } else if (!createOnly || !fresh.exists) {
        tx.set(entry.key, entry.value!, SetOptions(merge: true));
      }
    }
  }).timeout(const Duration(seconds: 20));
}

bool permitsRoomAccess(Map<String, dynamic> actor, String churchId, String? category) {
  if (actor['isBlocked'] == true || churchId.trim().isEmpty) return false;
  if (actor['role'] == 'superadmin') return true;
  if (legacyText(actor['churchId']).trim() != churchId.trim()) return false;
  if (actor['role'] == 'admin' || category == null || category.trim().isEmpty) return true;
  return KategorialConfig.same(actor['kelompok'], category);
}

bool permitsGlobalSongWrite(Map<String, dynamic> actor) =>
    actor['isBlocked'] != true && (actor['role'] == 'admin' || actor['role'] == 'superadmin');

Future<void> checkGlobalSongWrite(String? expectedUid) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || uid != expectedUid) throw StateError('Sesi login berubah.');
  final actor = await FirebaseFirestore.instance.collection('users').doc(uid)
      .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));
  if (FirebaseAuth.instance.currentUser?.uid != uid || UserManager().userId != uid ||
      !actor.exists || !permitsGlobalSongWrite(actor.data()!)) {
    throw StateError('Izin mengubah Buku Nyanyian sudah berubah.');
  }
}
