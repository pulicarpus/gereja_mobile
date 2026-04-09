import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'user_manager.dart'; 
import 'tambah_doa_page.dart'; 
import 'secrets.dart'; // 👇 Pastikan ini ada supaya osRestKey terbaca

class DoaPage extends StatefulWidget {
  const DoaPage({super.key});

  @override
  State<DoaPage> createState() => _DoaPageState();
}

class _DoaPageState extends State<DoaPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserManager _userManager = UserManager();

  // Kunci Rahasia OneSignal (Sama seperti di Chatroom)
  final String osRestKey = osRestKeySecret; 
  final String osAppId = "a9ff250a-56ef-413d-b825-67288008d614";

  // 👇 FUNGSI KIRIM NOTIF PRIBADI KE PEMILIK DOA 👇
  Future<void> _kirimNotifAmin(String targetUid, String namaPengirim, String isiDoa) async {
    if (osRestKey.isEmpty || targetUid.isEmpty) return;
    
    // Jangan kirim notif ke diri sendiri (kalau bos ngaminin doa sendiri)
    if (targetUid == _auth.currentUser?.uid) return;

    try {
      String snippet = isiDoa.length > 30 ? "${isiDoa.substring(0, 30)}..." : isiDoa;
      await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic $osRestKey'
        },
        body: jsonEncode({
          "app_id": osAppId,
          "include_external_user_ids": [targetUid], // Nembak spesifik ke UID si pembuat doa
          "headings": {"en": "Dukungan Doa 🙏"},
          "contents": {"en": "$namaPengirim baru saja mengaminkan doa Anda: \"$snippet\""}
        }),
      );
    } catch (e) {
      debugPrint("Gagal kirim notif Amin: $e");
    }
  }

  // 👇 LOGIKA AMIN DIPERBARUI 👇
  void _prosesAmen(String docId, List<dynamic> currentDaftarAmin, String ownerUid, String isiDoa) {
    String currentUserName = _userManager.userNama ?? "Jemaat";
    
    if (currentDaftarAmin.contains(currentUserName)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bos sudah mendukung doa ini.")));
      return;
    }

    _db.collection("prayers").doc(docId).update({
      "daftarAmin": FieldValue.arrayUnion([currentUserName])
    }).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Amin! Dukungan terkirim.")));
      // PANGGIL NOTIFNYA DI SINI
      _kirimNotifAmin(ownerUid, currentUserName, isiDoa);
    }).catchError((e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal memberikan Amin")));
    });
  }

  void _tampilkanDialogOpsi(Map<String, dynamic> doaData, String docId) {
    String myUid = _auth.currentUser?.uid ?? "";
    bool isPemilik = doaData['uid'] == myUid;
    bool canManage = isPemilik || _userManager.isAdmin() || _userManager.isSuperAdmin();

    if (!canManage) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 20),
          const Text("Opsi Permohonan Doa", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const Divider(),
          if (isPemilik)
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.orange),
              title: const Text("Edit Doa"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => TambahDoaPage(doaId: docId, existingData: doaData)));
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text("Hapus Doa", style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _konfirmasiHapus(docId);
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _konfirmasiHapus(String docId) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Hapus Doa"),
        content: const Text("Apakah Anda yakin ingin menghapus permohonan doa ini?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              _db.collection("prayers").doc(docId).delete().then((_) {
                Navigator.pop(c);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Berhasil dihapus")));
              });
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.white)),
          )
        ],
      )
    );
  }

  void _tampilkanDaftarAmin(List<dynamic> daftarAmin) {
    if (daftarAmin.isEmpty) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 16),
          Text("${daftarAmin.length} Orang Mengaminkan", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: daftarAmin.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.indigo, child: Icon(Icons.person, color: Colors.white, size: 20)),
                  title: Text(daftarAmin[index].toString(), style: const TextStyle(fontWeight: FontWeight.w500)),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String? churchId = _userManager.getChurchIdForCurrentView();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Permohonan Doa", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection("prayers").where("churchId", isEqualTo: churchId).orderBy("tanggal", descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.volunteer_activism, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text("Belum ada permohonan doa.", style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                ],
              ),
            );
          }

          String myUid = _auth.currentUser?.uid ?? "";
          var doaList = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            bool isPrivat = data['isPrivat'] ?? false;
            String ownerUid = data['uid'] ?? "";
            return !isPrivat || _userManager.isAdmin() || _userManager.isSuperAdmin() || ownerUid == myUid;
          }).toList();

          if (doaList.isEmpty) return Center(child: Text("Tidak ada doa yang dapat ditampilkan.", style: TextStyle(color: Colors.grey[600])));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: doaList.length,
            itemBuilder: (context, index) {
              var doc = doaList[index];
              var data = doc.data() as Map<String, dynamic>;
              String docId = doc.id;

              String ownerUid = data['uid'] ?? ""; // Ambil UID pemilik doa
              String nama = data['nama'] ?? "Jemaat";
              String isiDoa = data['isiDoa'] ?? "";
              bool isPrivat = data['isPrivat'] ?? false;
              List<dynamic> daftarAmin = data['daftarAmin'] ?? [];
              
              String tanggalStr = "";
              if (data['tanggal'] != null) {
                DateTime dt = (data['tanggal'] as Timestamp).toDate();
                tanggalStr = DateFormat('dd MMM yyyy, HH:mm').format(dt);
              }

              String currentUserName = _userManager.userNama ?? "Jemaat";
              bool hasAmened = daftarAmin.contains(currentUserName);

              return Card(
                elevation: 1, margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onLongPress: () => _tampilkanDialogOpsi(data, docId), 
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(backgroundColor: isPrivat ? Colors.red[100] : Colors.indigo[100], child: Icon(isPrivat ? Icons.lock : Icons.person, color: isPrivat ? Colors.red : Colors.indigo)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text(nama, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                      if (isPrivat) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)), child: const Text("Privat", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)))
                                    ],
                                  ),
                                  Text(tanggalStr, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(isiDoa, style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87)),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: () => _tampilkanDaftarAmin(daftarAmin),
                              child: Text(
                                daftarAmin.isEmpty ? "Belum ada dukungan" : "${daftarAmin.length} Orang Mengaminkan", 
                                style: TextStyle(color: daftarAmin.isEmpty ? Colors.grey[600] : Colors.indigo, fontSize: 13, fontWeight: FontWeight.bold, decoration: daftarAmin.isNotEmpty ? TextDecoration.underline : TextDecoration.none)
                              ),
                            ),
                            TextButton.icon(
                              // 👇 LEMPAR DATA ownerUid DAN isiDoa KE FUNGSI AMIN 👇
                              onPressed: hasAmened ? null : () => _prosesAmen(docId, daftarAmin, ownerUid, isiDoa),
                              icon: Icon(Icons.volunteer_activism, color: hasAmened ? Colors.grey : Colors.indigo, size: 20),
                              label: Text(hasAmened ? "Di-Amin-kan" : "Amin!", style: TextStyle(color: hasAmened ? Colors.grey : Colors.indigo, fontWeight: FontWeight.bold)),
                              style: TextButton.styleFrom(backgroundColor: hasAmened ? Colors.transparent : Colors.indigo.shade50, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
           Navigator.push(context, MaterialPageRoute(builder: (context) => const TambahDoaPage()));
        },
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}