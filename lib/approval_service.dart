import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ApprovalPending implements Exception {
  final String message;
  const ApprovalPending(this.message);
}
class ApprovalService {
  final FirebaseFunctions functions;
  final FirebaseAuth auth;
  ApprovalService({FirebaseFunctions? functions, FirebaseAuth? auth})
    : functions = functions ?? FirebaseFunctions.instance, auth = auth ?? FirebaseAuth.instance;
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('Sesi berakhir. Silakan masuk ulang.');
    try {
      final result = await functions.httpsCallable(name,
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30))).call(data);
      if (auth.currentUser?.uid != uid) throw StateError('Sesi berubah. Buka ulang halaman ini.');
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'not-found' || error.code == 'unimplemented') {
        throw StateError('Layanan persetujuan belum aktif. Hubungi Admin Gereja.');
      }
      if (error.code == 'deadline-exceeded' || error.code == 'unavailable') {
        throw TimeoutException('Hasil permohonan belum pasti. Periksa status sebelum mengirim ulang.');
      }
      throw StateError(error.message ?? 'Permohonan ditolak. Periksa data atau hubungi admin.');
    }
  }
}
