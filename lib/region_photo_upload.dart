import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'app_safety.dart';
import 'upload_support.dart';

Future<String> uploadRegionPhoto(String area, File photo, String folder) async {
  final uid = await checkRegionWrite(area);
  final metadata = await prepareUpload(photo);
  final id = FirebaseFirestore.instance
      .collection('inventaris_daerah')
      .doc()
      .id;
  final reference = FirebaseStorage.instance.ref(
    'daerah/${Uri.encodeComponent(area.trim())}/$folder/$id',
  );
  final task = reference.putFile(photo, metadata);
  try {
    await task.timeout(const Duration(seconds: 60));
  } on TimeoutException {
    await task.cancel();
    rethrow;
  }
  final url = await reference.getDownloadURL().timeout(
    const Duration(seconds: 20),
  );
  if (await checkRegionWrite(area) != uid) {
    throw StateError(
      'Sesi berubah saat mengunggah foto. Buka kembali halaman ini.',
    );
  }
  return url;
}
