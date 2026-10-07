import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'user_manager.dart';
import 'tambah_doa_page.dart';
import 'secrets.dart';
import 'prayer_feed.dart';

class DoaPage extends StatefulWidget {
  const DoaPage({super.key});

  @override
  State<DoaPage> createState() => _DoaPageState();
}

class _DoaPageState extends State<DoaPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserManager _userManager = UserManager();
  final TextEditingController _searchController = TextEditingController();

  final String osRestKey = osRestKeySecret;
  final String osAppId = "a9ff250a-56ef-413d-b825-67288008d614";

  String _searchQuery = "";
  String _filter = "Semua";
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _feed;
  String? _feedChurch, _feedUid;

  bool get _canViewPrivateChurchPrayers =>
      _userManager.isAdmin() || _userManager.isSuperAdmin() || _userManager.isGembala();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  DateTime? _tanggal(Map<String, dynamic> data) {
    final raw = data['tanggal'];
    return raw is Timestamp ? raw.toDate() : null;
  }

  List<dynamic> _daftarAmin(Map<String, dynamic> data) {
    final raw = data['daftarAmin'];
    return raw is Iterable ? List<dynamic>.from(raw) : <dynamic>[];
  }

  Future<bool> _kirimNotifAmin(
    String targetUid,
    String namaPengirim,
    String isiDoa,
  ) async {
    if (osRestKey.isEmpty || targetUid.isEmpty) return false;
    if (targetUid == _auth.currentUser?.uid) return true;

    try {
      final snippet = isiDoa.length > 30 ? "${isiDoa.substring(0, 30)}..." : isiDoa;
      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic $osRestKey',
        },
        body: jsonEncode({
          "app_id": osAppId,
          "include_external_user_ids": [targetUid],
          "headings": {"en": "Dukungan Doa 🙏"},
          "contents": {"en": "$namaPengirim baru saja mengaminkan doa Anda: \"$snippet\""},
          "data": {"type": "doa"},
        }),
      );
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      if (!ok) debugPrint("Notifikasi Amin ditolak: ${response.statusCode}");
      return ok;
    } catch (e) {
      debugPrint("Gagal kirim notif Amin: $e");
      return false;
    }
  }

  Future<void> _prosesAmen(
    String docId,
    List<dynamic> currentDaftarAmin,
    String ownerUid,
    String isiDoa,
  ) async {
    final currentUid = _auth.currentUser?.uid ?? "";
    if (currentUid.isEmpty) {
      _showSnack("Silakan login kembali.", color: Colors.red);
      return;
    }
    if (ownerUid == currentUid) {
      _showSnack("Pemilik doa tidak perlu mengaminkan doanya sendiri.");
      return;
    }

    final currentUserName = (_userManager.userNama ?? "Jemaat").trim().isEmpty
        ? "Jemaat"
        : (_userManager.userNama ?? "Jemaat").trim();

    // Data lama menyimpan nama, bukan UID. Pertahankan format lama agar aplikasi
    // yang sudah terpasang tetap kompatibel.
    if (currentDaftarAmin.any((e) => e.toString() == currentUserName)) {
      _showSnack("Anda sudah mendukung doa ini.");
      return;
    }

    try {
      await _db.collection("prayers").doc(docId).update({
        "daftarAmin": FieldValue.arrayUnion([currentUserName]),
      });
      _showSnack("Amin! Dukungan terkirim.");
      await _kirimNotifAmin(ownerUid, currentUserName, isiDoa);
    } catch (e) {
      _showSnack("Gagal memberikan Amin.", color: Colors.red);
    }
  }

  void _tampilkanDialogOpsi(Map<String, dynamic> doaData, String docId) {
    final myUid = _auth.currentUser?.uid ?? "";
    final ownerUid = doaData['uid']?.toString() ?? "";
    final isPemilik = ownerUid == myUid;
    final canDelete = isPemilik || _userManager.isAdmin() || _userManager.isSuperAdmin();

    if (!canDelete) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Opsi Permohonan Doa",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const Divider(),
            if (isPemilik)
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.orange),
                title: const Text("Edit Doa"),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TambahDoaPage(
                        doaId: docId,
                        existingData: doaData,
                      ),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Hapus Doa", style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetContext);
                _konfirmasiHapus(docId, ownerUid);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _konfirmasiHapus(String docId, String ownerUid) async {
    final currentUid = _auth.currentUser?.uid ?? "";
    final canDelete = ownerUid == currentUid ||
        _userManager.isAdmin() ||
        _userManager.isSuperAdmin();

    if (!canDelete) {
      _showSnack("Anda tidak memiliki izin untuk menghapus doa ini.", color: Colors.red);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Hapus Doa"),
        content: const Text("Apakah Anda yakin ingin menghapus permohonan doa ini?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Hapus"),
          ),
        ],
      ),
    ) ?? false;

    if (!confirmed) return;

    try {
      await _db.collection("prayers").doc(docId).delete();
      _showSnack("Permohonan doa berhasil dihapus.");
    } catch (e) {
      _showSnack("Gagal menghapus permohonan doa.", color: Colors.red);
    }
  }

  void _tampilkanDaftarAmin(List<dynamic> daftarAmin) {
    if (daftarAmin.isEmpty) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "${daftarAmin.length} Orang Mengaminkan",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: daftarAmin.length,
                itemBuilder: (_, index) => ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.indigo,
                    child: Icon(Icons.person, color: Colors.white, size: 20),
                  ),
                  title: Text(
                    daftarAmin[index].toString(),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _prayers(String church, String uid) {
    if (_feed == null || _feedChurch != church || _feedUid != uid) {
      _feedChurch = church; _feedUid = uid; _feed = PrayerFeed().watch(church);
    }
    return _feed!;
  }

  @override
  Widget build(BuildContext context) {
    final churchId = _userManager.getChurchIdForCurrentView();
    final myUid = _auth.currentUser?.uid ?? "";

    if (churchId == null || churchId.trim().isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Permohonan Doa"),
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text("Data gereja tidak valid.")),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          "Permohonan Doa",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: const PreferredSize(preferredSize: Size.fromHeight(48), child: Padding(
          padding: EdgeInsets.all(8), child: Text('Doa publik lama tanpa status privasi perlu diperiksa admin sebelum muncul untuk semua anggota.',
            style: TextStyle(color: Colors.white70, fontSize: 11), textAlign: TextAlign.center))),
      ),
      body: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        key: ValueKey('$churchId|$myUid'),
        stream: _prayers(churchId, myUid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            debugPrint("Gagal memuat pokok doa: ${snapshot.error}");
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 52, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text(
                      "Pokok doa gagal dimuat. Periksa koneksi atau coba lagi.",
                      textAlign: TextAlign.center,
                    ),
                    TextButton(onPressed: () => setState(() { _feed = null; }), child: const Text('Coba lagi')),
                  ],
                ),
              ),
            );
          }

          final docs = snapshot.data?.toList() ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          docs.sort((a, b) {
            final ad = _tanggal(a.data() as Map<String, dynamic>) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bd = _tanggal(b.data() as Map<String, dynamic>) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bd.compareTo(ad);
          });

          final visible = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final isPrivat = data['isPrivat'] == true;
            final ownerUid = data['uid']?.toString() ?? "";
            final nama = (data['nama'] ?? "Jemaat").toString();
            final isi = (data['isiDoa'] ?? "").toString();
            final daftar = _daftarAmin(data);
            final currentName = (_userManager.userNama ?? "Jemaat").trim();

            final allowed = !isPrivat ||
                _canViewPrivateChurchPrayers ||
                ownerUid == myUid;
            if (!allowed) return false;

            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              if (!nama.toLowerCase().contains(q) &&
                  !isi.toLowerCase().contains(q)) {
                return false;
              }
            }

            if (_filter == "Doa Saya" && ownerUid != myUid) return false;
            if (_filter == "Privat Saya" && !(ownerUid == myUid && isPrivat)) {
              return false;
            }
            if (_filter == "Belum Saya Amin") {
              final hasAmened = daftar.any((e) => e.toString() == currentName);
              if (ownerUid == myUid || hasAmened) return false;
            }
            return true;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Cari nama atau isi pokok doa...",
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = "");
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    isDense: true,
                  ),
                  onChanged: (value) =>
                      setState(() => _searchQuery = value.trim()),
                ),
              ),
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: ["Semua", "Doa Saya", "Belum Saya Amin", "Privat Saya"]
                      .map(
                        (label) => Padding(
                          padding: const EdgeInsets.only(right: 7),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: _filter == label,
                            onSelected: (_) => setState(() => _filter = label),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.volunteer_activism,
                              size: 72,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              docs.isEmpty
                                  ? "Belum ada permohonan doa."
                                  : "Tidak ada pokok doa yang cocok.",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 90),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final doc = visible[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final docId = doc.id;
                          final ownerUid = data['uid']?.toString() ?? "";
                          final nama = (data['nama'] ?? "Jemaat").toString();
                          final isiDoa = (data['isiDoa'] ?? "").toString();
                          final isPrivat = data['isPrivat'] == true;
                          final daftarAmin = _daftarAmin(data);
                          final dt = _tanggal(data);
                          final tanggalStr = dt == null
                              ? "Tanggal tidak tersedia"
                              : DateFormat('dd MMM yyyy, HH:mm').format(dt);
                          final currentUserName =
                              (_userManager.userNama ?? "Jemaat").trim();
                          final hasAmened = daftarAmin.any(
                            (e) => e.toString() == currentUserName,
                          );
                          final isOwner = ownerUid == myUid;

                          return Card(
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(15),
                              onLongPress: () =>
                                  _tampilkanDialogOpsi(data, docId),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: isPrivat
                                              ? Colors.red[100]
                                              : Colors.indigo[100],
                                          child: Icon(
                                            isPrivat
                                                ? Icons.lock
                                                : Icons.person,
                                            color: isPrivat
                                                ? Colors.red
                                                : Colors.indigo,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      nama,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ),
                                                  if (isOwner)
                                                    _badge(
                                                      "DOA SAYA",
                                                      Colors.indigo,
                                                    ),
                                                  if (isPrivat) ...[
                                                    const SizedBox(width: 5),
                                                    _badge(
                                                      "PRIVAT",
                                                      Colors.red,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                tanggalStr,
                                                style: TextStyle(
                                                  color: Colors.grey[500],
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      isiDoa,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        height: 1.5,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Divider(height: 1),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        GestureDetector(
                                          onTap: () =>
                                              _tampilkanDaftarAmin(daftarAmin),
                                          child: Text(
                                            daftarAmin.isEmpty
                                                ? "Belum ada dukungan"
                                                : "${daftarAmin.length} Orang Mengaminkan",
                                            style: TextStyle(
                                              color: daftarAmin.isEmpty
                                                  ? Colors.grey[600]
                                                  : Colors.indigo,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              decoration: daftarAmin.isEmpty
                                                  ? TextDecoration.none
                                                  : TextDecoration.underline,
                                            ),
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: isOwner || hasAmened
                                              ? null
                                              : () => _prosesAmen(
                                                    docId,
                                                    daftarAmin,
                                                    ownerUid,
                                                    isiDoa,
                                                  ),
                                          icon: Icon(
                                            Icons.volunteer_activism,
                                            color: isOwner || hasAmened
                                                ? Colors.grey
                                                : Colors.indigo,
                                            size: 20,
                                          ),
                                          label: Text(
                                            isOwner
                                                ? "Doa Saya"
                                                : hasAmened
                                                    ? "Sudah Saya Amin"
                                                    : "Amin!",
                                            style: TextStyle(
                                              color: isOwner || hasAmened
                                                  ? Colors.grey
                                                  : Colors.indigo,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          style: TextButton.styleFrom(
                                            backgroundColor:
                                                isOwner || hasAmened
                                                    ? Colors.transparent
                                                    : Colors.indigo.shade50,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TambahDoaPage()),
          );
        },
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _badge(String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color.shade700,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

