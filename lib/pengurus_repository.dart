import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'user_manager.dart';
import 'pengurus_support.dart';

class PengurusRepository {
  final String churchId;
  final String sessionId;
  final bool readOnly;
  final FirebaseFirestore db = FirebaseFirestore.instance;
  PengurusRepository(this.churchId, this.sessionId, {this.readOnly = false});
  DocumentReference<Map<String, dynamic>> get church =>
      db.collection('churches').doc(churchId);
  bool get canEdit {
    final user = UserManager();
    return user.userId == sessionId &&
        pengurusCanEdit(
          userId: user.userId,
          signedInId: FirebaseAuth.instance.currentUser?.uid,
          role: user.userRole,
          churchId: churchId,
          currentChurchId: user.getChurchIdForCurrentView(),
          readOnly: readOnly,
        );
  }

  void checkSession() {
    if (!canEdit)
      throw StateError(
        'Sesi atau izin sudah berubah. Buka kembali halaman Pengurus.',
      );
  }

  Future<void> checkAccess() async {
    checkSession();
    final user = await db
        .collection('users')
        .doc(sessionId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 20));
    checkSession();
    final data = user.data() ?? <String, dynamic>{};
    final role = data['role'];
    if (!user.exists ||
        data['isBlocked'] == true ||
        (role != 'admin' && role != 'superadmin') ||
        (role == 'admin' && pengurusText(data['churchId']) != churchId)) {
      throw StateError(
        'Anda tidak memiliki izin mengubah pengurus gereja ini.',
      );
    }
  }

  Future<void> savePerson(
    DocumentReference<Map<String, dynamic>> doc,
    Map<String, dynamic> data, {
    File? photo,
    required String photoKey,
    String? oldPhoto,
    bool removePhoto = false,
    String? mirrorPhotoKey,
  }) async {
    await checkAccess();
    String? uploadedPath;
    try {
      if (photo != null) {
        uploadedPath =
            'gereja/$churchId/pengurus/${church.collection('bpj_seksi').doc().id}.jpg';
        final ref = FirebaseStorage.instance.ref(uploadedPath);
        final task = ref.putFile(
          photo,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        try {
          await task.timeout(const Duration(seconds: 60));
        } on TimeoutException {
          await task.cancel();
          rethrow;
        }
        data[photoKey] = await ref.getDownloadURL().timeout(
          const Duration(seconds: 20),
        );
      } else if (removePhoto) {
        data[photoKey] = '';
      }
      if (mirrorPhotoKey != null && data.containsKey(photoKey))
        data[mirrorPhotoKey] = data[photoKey];
      await checkAccess();
      // update protects against resurrecting a deleted church/section/person.
      await doc.update(data).timeout(const Duration(seconds: 30));
    } on FirebaseException catch (e) {
      // Only reclaim this operation's new file on a definitive rejection.
      // Timeouts/unknown outcomes must not remove a possibly committed photo.
      if (uploadedPath != null &&
          [
            'permission-denied',
            'not-found',
            'invalid-argument',
          ].contains(e.code)) {
        try {
          await FirebaseStorage.instance
              .ref(uploadedPath)
              .delete()
              .timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> saveDynamicPerson(
    DocumentReference<Map<String, dynamic>> doc,
    Map<String, dynamic> data, {
    required bool create,
    File? photo,
    String? oldPhoto,
    bool removePhoto = false,
  }) async {
    if (!create) {
      await savePerson(
        doc,
        data,
        photo: photo,
        photoKey: 'fotoUrl',
        oldPhoto: oldPhoto,
        removePhoto: removePhoto,
      );
      return;
    }
    await checkAccess();
    if (photo != null) {
      final ref = FirebaseStorage.instance.ref(
        'gereja/$churchId/pengurus/${church.collection('bpj_seksi').doc().id}.jpg',
      );
      final task = ref.putFile(
        photo,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      try {
        await task.timeout(const Duration(seconds: 60));
      } on TimeoutException {
        await task.cancel();
        rethrow;
      }
      data['fotoUrl'] = await ref.getDownloadURL().timeout(
        const Duration(seconds: 20),
      );
    } else {
      data['fotoUrl'] = '';
    }
    await checkAccess();
    await db
        .runTransaction((tx) async {
          final parent = await tx.get(church);
          final existing = await tx.get(doc);
          checkSession();
          if (!parent.exists) throw StateError('Gereja sudah tidak tersedia.');
          if (existing.exists)
            return; // Stable ID makes uncertain retries safe.
          tx.set(doc, {...data, 'createdAt': FieldValue.serverTimestamp()});
        })
        .timeout(const Duration(seconds: 30));
  }

  Future<void> changeMember(
    DocumentReference<Map<String, dynamic>> doc,
    List<dynamic> original,
    int? index,
    Map<String, dynamic>? person, {
    File? photo,
    String? oldPhoto,
    bool removePhoto = false,
    required String operationId,
  }) async {
    await checkAccess();
    if (person != null) {
      if (photo != null) {
        final ref = FirebaseStorage.instance.ref(
          'gereja/$churchId/pengurus/$operationId.jpg',
        );
        final task = ref.putFile(
          photo,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        try {
          await task.timeout(const Duration(seconds: 60));
        } on TimeoutException {
          await task.cancel();
          rethrow;
        }
        person['img'] = await ref.getDownloadURL().timeout(
          const Duration(seconds: 20),
        );
      } else {
        person['img'] = removePhoto ? '' : oldPhoto ?? '';
      }
    }
    await checkAccess();
    await db
        .runTransaction((tx) async {
          final snapshot = await tx.get(doc);
          checkSession();
          if (!snapshot.exists) throw StateError('Seksi sudah dihapus.');
          final raw = snapshot.data()?['anggota'];
          if (raw != null && raw is! List)
            throw StateError(
              'Format daftar anggota tidak valid. Hubungi administrator.',
            );
          final latest = pengurusMembers(raw);
          final next = changePengurusMember(
            latest: latest,
            original: original,
            index: index,
            replacement: person,
          );
          tx.update(doc, {'anggota': next});
        })
        .timeout(const Duration(seconds: 30));
  }
}
