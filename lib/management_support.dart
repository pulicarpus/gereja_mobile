import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'kategorial_config.dart';

String managementText(dynamic value, [String fallback = '']) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}
bool managementId(String value) => value.isNotEmpty && !value.contains('/');
String managementChurchName(Map<String, dynamic> data) => managementText(
  data['namaGereja'], managementText(data['nama'], managementText(data['churchName'], 'Gereja Tanpa Nama')));

class ManagementRecord {
  final String id;
  final Map<String, dynamic> data;
  ManagementRecord(this.id, Map<String, dynamic> data) : data = Map.unmodifiable(data);
}
class ManagementAccess {
  final String uid, role, churchId;
  const ManagementAccess(this.uid, this.role, this.churchId);
  bool get superAdmin => role == 'superadmin';
  bool get admin => role == 'admin' || superAdmin;
  bool canView(Map<String, dynamic> target) => admin && (superAdmin ||
    (managementId(churchId) && managementText(target['churchId']) == churchId));
  bool canManage(Map<String, dynamic> target) => canView(target) &&
    managementText(target['role'], 'user') != 'superadmin' &&
    (superAdmin || managementText(target['role'], 'user') == 'user');
}

// Called again against server documents inside each transaction.
Map<String, dynamic> managementUserPatch(ManagementAccess actor, String targetId,
    Map<String, dynamic> target, String field, dynamic value) {
  if (!actor.canManage(target)) throw StateError('Anda tidak berhak mengubah akun ini.');
  if (field == 'role') {
    if (targetId == actor.uid) throw StateError('Hak akses akun sendiri tidak dapat diubah di sini.');
    if (value != 'admin' && value != 'user') throw StateError('Role tidak didukung.');
    if (value == 'admin' && !managementId(managementText(target['churchId']))) {
      throw StateError('Tetapkan gereja terlebih dahulu sebelum mengangkat admin.');
    }
    return {'role': value, 'isPengurus': false};
  }
  if (field == 'kelompok') {
    if (!KategorialConfig.pilihanJemaat.contains(value)) throw StateError('Kategorial tidak valid.');
    return {'kelompok': value, 'isPengurus': false};
  }
  if (field == 'isPengurus') {
    if (managementText(target['role'], 'user') != 'user' ||
        !KategorialConfig.isPelayanan(target['kelompok']) || value is! bool) {
      throw StateError('Pengurus lokal harus jemaat dengan kategorial pelayanan.');
    }
    return {'isPengurus': value};
  }
  if (field == 'adminDaerahArea') {
    if (!actor.superAdmin) throw StateError('Hanya Superadmin dapat mengatur jabatan daerah.');
    return {'adminDaerahArea': managementText(value)};
  }
  if (field == 'churchId') {
    if (!actor.superAdmin || targetId == actor.uid) throw StateError('Perpindahan gereja akun ini tidak diizinkan.');
    final id = managementText(value);
    if (!managementId(id)) throw StateError('Gereja tujuan tidak valid.');
    if (managementText(target['churchId']) == id) return {};
    if (managementText(target['jemaatId']).isNotEmpty) {
      throw StateError('Akun masih tertaut ke buku induk. Selesaikan tautan lama terlebih dahulu; data jemaat tidak dipindah otomatis.');
    }
    return {'churchId': id, 'isPengurus': false};
  }
  throw StateError('Tindakan tidak didukung.');
}
bool managementUnchanged(Map<String, dynamic> expected, Map<String, dynamic> actual,
    Iterable<String> fields) => fields.every((key) => expected[key] == actual[key]);
String managementUserScope(ManagementAccess actor, String? view) {
  final church = actor.superAdmin ? managementText(view) : actor.churchId;
  if (!managementId(church)) throw StateError('Pilih gereja terlebih dahulu. Daftar semua akun tidak dibuka otomatis.');
  return church;
}
void managementCheckBook(Map<String, dynamic>? book, String uid) {
  if (book == null || managementText(book['uid']) != uid) {
    throw StateError('Pemilik tautan buku induk tidak cocok. Kategorial belum diubah; periksa sinkronisasi terlebih dahulu.');
  }
}
bool managementUncertain(Object error) => error is TimeoutException ||
  (error is FirebaseException && ['deadline-exceeded', 'unavailable', 'unknown'].contains(error.code));
String managementError(Object error) {
  if (error is StateError) return error.message.toString();
  if (managementUncertain(error)) return 'Koneksi terlalu lama. Jika sedang menyimpan, hasil belum dapat dipastikan. Muat ulang data sebelum mencoba lagi.';
  if (error is FirebaseException && error.code == 'permission-denied') return 'Akses ditolak. Periksa sesi atau hubungi Superadmin.';
  return 'Operasi gagal. Periksa koneksi dan coba lagi.';
}
