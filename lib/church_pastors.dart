import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_safety.dart';
import 'user_manager.dart';

class ChurchPastor {
  final String id, name, photo, wa, fb, ig, tiktok, yt, uid, memberId;
  const ChurchPastor({
    required this.id,
    required this.name,
    this.photo = '',
    this.wa = '',
    this.fb = '',
    this.ig = '',
    this.tiktok = '',
    this.yt = '',
    this.uid = '',
    this.memberId = '',
  });
  factory ChurchPastor.fromMap(Map<String, dynamic> data) => ChurchPastor(
    id: legacyText(data['id']).trim(),
    name: legacyText(data['name']).trim(),
    photo: legacyText(data['photo']).trim(),
    wa: legacyText(data['wa']).trim(),
    fb: legacyText(data['fb']).trim(),
    ig: legacyText(data['ig']).trim(),
    tiktok: legacyText(data['tiktok']).trim(),
    yt: legacyText(data['yt']).trim(),
    uid: legacyText(data['uid']).trim(),
    memberId: legacyText(data['memberId']).trim(),
  );
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'photo': photo,
    'wa': wa,
    'fb': fb,
    'ig': ig,
    'tiktok': tiktok,
    'yt': yt,
    if (uid.isNotEmpty) 'uid': uid,
    if (memberId.isNotEmpty) 'memberId': memberId,
  };
  bool same(ChurchPastor other) =>
      toMap().entries.every((e) => other.toMap()[e.key] == e.value);
}

List<ChurchPastor> churchPastors(Map<String, dynamic> church) {
  if (church['gembalaProfiles'] is List) {
    return (church['gembalaProfiles'] as List)
        .whereType<Map>()
        .map((p) => ChurchPastor.fromMap(Map<String, dynamic>.from(p)))
        .where((p) => p.id.isNotEmpty && p.name.isNotEmpty)
        .toList();
  }
  final name = legacyText(church['namaGembala']).trim();
  if (name.isEmpty) return [];
  return [
    ChurchPastor(
      id: 'legacy-primary',
      name: name,
      photo: legacyText(church['fotoGembalaUrl']).trim(),
      wa: legacyText(church['waGembala']).trim(),
      fb: legacyText(church['fbGembala']).trim(),
      ig: legacyText(church['igGembala']).trim(),
      tiktok: legacyText(church['tiktokGembala']).trim(),
      yt: legacyText(church['ytGembala']).trim(),
    ),
  ];
}

class ChurchPastorsRepository {
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  final String churchId;
  ChurchPastorsRepository(
    this.churchId, {
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  }) : db = db ?? FirebaseFirestore.instance,
       auth = auth ?? FirebaseAuth.instance;
  String newId() => db.collection('churches').doc().id;
  void _session(String? uid) {
    if (uid == null ||
        auth.currentUser?.uid != uid ||
        UserManager().userId != uid ||
        UserManager().getChurchIdForCurrentView() != churchId) {
      throw StateError('Sesi atau gereja aktif berubah. Buka ulang halaman.');
    }
  }

  Future<void> checkAccess() async {
    final uid = auth.currentUser?.uid;
    _session(uid);
    final actor = await db
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    _session(uid);
    if (!actor.exists || !permitsChurchWrite(actor.data()!, churchId)) {
      throw StateError(
        'Hanya admin gereja atau superadmin yang dapat mengatur gembala.',
      );
    }
  }

  Future<void> save(ChurchPastor profile, {ChurchPastor? expected}) =>
      _change(profile, expected: expected, remove: false);
  Future<void> remove(ChurchPastor expected) =>
      _change(expected, expected: expected, remove: true);
  Future<void> _change(
    ChurchPastor profile, {
    ChurchPastor? expected,
    required bool remove,
  }) async {
    if (profile.id.isEmpty || profile.name.trim().isEmpty)
      throw StateError('Nama gembala wajib diisi.');
    final uid = auth.currentUser?.uid;
    _session(uid);
    final ref = db.collection('churches').doc(churchId);
    await db
        .runTransaction((tx) async {
          final actor = await tx.get(db.collection('users').doc(uid));
          final snapshot = await tx.get(ref);
          _session(uid);
          if (!actor.exists || !permitsChurchWrite(actor.data()!, churchId))
            throw StateError('Izin admin sudah berubah.');
          if (!snapshot.exists || snapshot.data()?['isArchived'] == true)
            throw StateError('Gereja sudah tidak tersedia.');
          final profiles = churchPastors(snapshot.data()!);
          final index = profiles.indexWhere((p) => p.id == profile.id);
          if (expected != null &&
              (index < 0 || !profiles[index].same(expected))) {
            throw StateError(
              'Profil gembala sudah berubah. Muat ulang sebelum menyimpan.',
            );
          }
          if (index >= 0 &&
              (profiles[index].uid != profile.uid ||
                  profiles[index].memberId != profile.memberId)) {
            throw StateError(
              'Tautan akun hanya dapat diatur melalui Hubungkan Gembala.',
            );
          }
          if (index < 0 &&
              (profile.uid.isNotEmpty || profile.memberId.isNotEmpty)) {
            throw StateError('Gunakan Hubungkan Gembala untuk menautkan akun.');
          }
          if (remove) {
            if (profiles[index].uid.isNotEmpty) {
              throw StateError(
                'Profil tertaut tidak dapat dihapus. Gunakan perpindahan gembala.',
              );
            }
            profiles.removeAt(index);
          } else if (index >= 0) {
            if (expected == null && !profiles[index].same(profile))
              throw StateError('Profil sudah ada. Muat ulang dahulu.');
            profiles[index] = profile;
          } else {
            profiles.add(profile);
          }
          tx.update(ref, churchPastorPatch(profiles));
        })
        .timeout(const Duration(seconds: 20));
  }
}

/// Mirrors only the first profile for older readers, without losing other pastors.
Map<String, dynamic> churchPastorPatch(List<ChurchPastor> profiles) {
  final primary = profiles.isEmpty
      ? const ChurchPastor(id: '', name: '')
      : profiles.first;
  return {
    'gembalaProfiles': profiles.map((p) => p.toMap()).toList(),
    'namaGembala': primary.name,
    'fotoGembalaUrl': primary.photo.isEmpty ? null : primary.photo,
    'waGembala': primary.wa,
    'fbGembala': primary.fb,
    'igGembala': primary.ig,
    'tiktokGembala': primary.tiktok,
    'ytGembala': primary.yt,
  };
}
