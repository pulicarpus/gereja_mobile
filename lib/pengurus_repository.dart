import 'upload_support.dart';
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'user_manager.dart';
import 'pengurus_support.dart';
import 'app_safety.dart';
import 'region_photo_upload.dart';

class PengurusRepository {
  final String churchId;
  final String sessionId;
  final bool readOnly;
  final String? regionName;
  final FirebaseFirestore db = FirebaseFirestore.instance;
  PengurusRepository(this.churchId, this.sessionId, {this.readOnly = false})
    : regionName = null;
  PengurusRepository.daerah(
    String area,
    this.sessionId, {
    this.readOnly = false,
    String? documentId,
  }) : regionName = area.trim(),
       churchId = documentId ?? pengurusRegionId(area);
  bool get isRegion => regionName != null;
  String get seksiCollection => isRegion ? 'komisi' : 'bpj_seksi';
  String get sectionNameKey => isRegion ? 'namaKomisi' : 'namaSeksi';
  String get corePrefix => isRegion ? 'bphd' : 'bpj';
  DocumentReference<Map<String, dynamic>> get church => db
      .collection(isRegion ? 'struktur_pengurus_daerah' : 'churches')
      .doc(churchId);
  bool get canEdit {
    final user = UserManager();
    if (isRegion) {
      return pengurusDaerahCanEdit(
        userId: user.userId,
        signedInId: FirebaseAuth.instance.currentUser?.uid,
        sessionId: sessionId,
        role: user.userRole,
        area: regionName!,
        adminArea: user.adminDaerahArea,
        readOnly: readOnly,
      );
    }
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
    if (isRegion) {
      final uid = await checkRegionWrite(regionName!);
      if (uid != sessionId) throw StateError('Sesi pengurus daerah berubah.');
      checkSession();
      return;
    }
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
    if (isRegion) {
      final payload = {...data, 'daerah': regionName};
      if (photo != null) {
        payload[photoKey] = await uploadRegionPhoto(
          regionName!,
          photo,
          'pengurus',
        );
      } else if (removePhoto) {
        payload[photoKey] = '';
      }
      await saveRegionChanges(
        regionName!,
        {doc: payload},
        requireExisting: doc.path != church.path,
        allowPastors: false,
      );
      return;
    }
    String? uploadedPath;
    try {
      if (photo != null) {
        uploadedPath =
            'gereja/$churchId/pengurus/${church.collection('bpj_seksi').doc().id}.jpg';
        final ref = FirebaseStorage.instance.ref(uploadedPath);
        final task = ref.putFile(photo, await prepareUpload(photo));
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
    if (isRegion) {
      final payload = {
        ...data,
        'daerah': regionName,
        'fotoUrl': photo == null
            ? ''
            : await uploadRegionPhoto(regionName!, photo, 'pengurus'),
        'createdAt': FieldValue.serverTimestamp(),
      };
      await saveRegionChanges(
        regionName!,
        {
          church: {'daerah': regionName},
          doc: payload,
        },
        createOnly: true,
        allowPastors: false,
      );
      return;
    }
    if (photo != null) {
      final ref = FirebaseStorage.instance.ref(
        'gereja/$churchId/pengurus/${church.collection('bpj_seksi').doc().id}.jpg',
      );
      final task = ref.putFile(photo, await prepareUpload(photo));
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
        if (isRegion) {
          person['img'] = await uploadRegionPhoto(
            regionName!,
            photo,
            'pengurus',
          );
        } else {
          final ref = FirebaseStorage.instance.ref(
            'gereja/$churchId/pengurus/$operationId.jpg',
          );
          final task = ref.putFile(photo, await prepareUpload(photo));
          try {
            await task.timeout(const Duration(seconds: 60));
          } on TimeoutException {
            await task.cancel();
            rethrow;
          }
          person['img'] = await ref.getDownloadURL().timeout(
            const Duration(seconds: 20),
          );
        }
      } else {
        person['img'] = removePhoto ? '' : oldPhoto ?? '';
      }
    }
    await checkAccess();
    await db
        .runTransaction((tx) async {
          if (isRegion) {
            final actor = await tx.get(db.collection('users').doc(sessionId));
            if (!actor.exists ||
                !permitsRegionWrite(actor.data()!, regionName!)) {
              throw StateError('Izin pengurus daerah berubah.');
            }
          }
          final snapshot = await tx.get(doc);
          checkSession();
          if (!snapshot.exists) throw StateError('Seksi sudah dihapus.');
          if (isRegion && snapshot.data()?['daerah'] != regionName) {
            throw StateError('Komisi bukan milik daerah ini.');
          }
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
