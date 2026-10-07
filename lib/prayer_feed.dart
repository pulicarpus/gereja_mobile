import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

bool prayerModerator(Map<String, dynamic> account, String church) => account['isBlocked'] != true &&
  (account['role'] == 'superadmin' || (account['churchId'] == church && ['admin', 'gembala'].contains(account['role'])));

// Ordinary users never subscribe to a query that could return another user's
// private prayer. Privilege comes from the live account, not UserManager cache.
class PrayerFeed {
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  PrayerFeed({FirebaseFirestore? firestore, FirebaseAuth? firebaseAuth})
    : db = firestore ?? FirebaseFirestore.instance, auth = firebaseAuth ?? FirebaseAuth.instance;
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watch(String church) {
    final uid = auth.currentUser?.uid;
    if (uid == null) return Stream.error(StateError('Silakan login kembali.'));
    late StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>> controller;
    StreamSubscription? accountSub, authSub;
    final queries = <StreamSubscription>[];
    var generation = 0, stopped = false;
    Future<void> clearQueries() async {
      final old = queries.toList(); queries.clear();
      await Future.wait(old.map((s) => s.cancel()));
    }
    controller = StreamController(onListen: () {
      authSub = auth.authStateChanges().listen((user) async {
        if (user?.uid == uid || stopped) return;
        generation++; controller.add([]); await clearQueries();
        if (!stopped) controller.addError(StateError('Sesi berubah. Silakan buka ulang halaman doa.'));
      });
      accountSub = db.collection('users').doc(uid).snapshots(includeMetadataChanges: true).listen((snapshot) async {
        final current = ++generation;
        controller.add([]); await clearQueries();
        if (stopped || current != generation || auth.currentUser?.uid != uid) return;
        if (snapshot.metadata.isFromCache) return;
        final data = snapshot.data();
        if (data == null || data['isBlocked'] == true || (data['role'] != 'superadmin' && data['churchId'] != church)) {
          controller.addError(StateError('Akses doa berubah. Silakan masuk ulang.')); return;
        }
        final base = db.collection('prayers').where('churchId', isEqualTo: church);
        final sources = prayerModerator(data, church) ? [base] : [
          base.where('isPrivat', isEqualTo: false), base.where('uid', isEqualTo: uid)];
        final results = <int, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        for (var i = 0; i < sources.length; i++) {
          final index = i;
          queries.add(sources[i].snapshots().listen((result) {
            if (stopped || generation != current || auth.currentUser?.uid != uid) return;
            results[index] = result.docs;
            if (results.length != sources.length) return;
            final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
            for (final rows in results.values) { for (final row in rows) { merged[row.id] = row; } }
            controller.add(merged.values.toList());
          }, onError: (Object error) {
            if (!stopped && generation == current) { controller.add([]); controller.addError(error); }
          }));
        }
      }, onError: (Object error) async { if (!stopped) { generation++; controller.add([]); await clearQueries(); if (!stopped) controller.addError(error); } });
    }, onCancel: () async {
      stopped = true; generation++; await clearQueries(); await accountSub?.cancel(); await authSub?.cancel();
    });
    return controller.stream;
  }
}
