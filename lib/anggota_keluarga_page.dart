import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'user_manager.dart';
// 👇 IMPORT SUDAH DIAKTIFKAN 👇
import 'add_edit_jemaat_page.dart';
import 'pilih_jemaat_page.dart'; 
import 'detail_jemaat_page.dart';

class AnggotaKeluargaPage extends StatefulWidget {
  final String idKepalaKeluarga;
  final String namaKepalaKeluarga;

  const AnggotaKeluargaPage({
    super.key, 
    required this.idKepalaKeluarga, 
    required this.namaKepalaKeluarga
  });

  @override
  State<AnggotaKeluargaPage> createState() => _AnggotaKeluargaPageState();
}

class _AnggotaKeluargaPageState extends State<AnggotaKeluargaPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final UserManager _userManager = UserManager();
  
  String? _churchId;

  @override
  void initState() {
    super.initState();
    _churchId = _userManager.getChurchIdForCurrentView();
  }

  int _getSortWeight(String? status) {
    switch (status) {
      case "Kepala Keluarga": return 0;
      case "Istri": return 1;
      case "Anak": return 2;
      default: return 3;
    }
  }

  void _showAddMemberOptionsDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            const Text("Tambah Anggota Keluarga", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.search, color: Colors.indigo),
              title: const Text("Pilih dari Daftar Jemaat"),
              onTap: () {
                Navigator.pop(context);
                _pilihDariDaftarJemaat();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add, color: Colors.green),
              title: const Text("Tambah Anggota Baru (Manual)"),
              onTap: () {
                Navigator.pop(context);
                // 👇 TOMBOL TAMBAH MANUAL SUDAH DISAMBUNG 👇
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => AddEditJemaatPage(idKepalaKeluargaBaru: widget.idKepalaKeluarga)
                ));
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _pilihDariDaftarJemaat() async {
    // 👇 TOMBOL PILIH DARI DAFTAR SUDAH DISAMBUNG 👇
    final selectedJemaat = await Navigator.push(context, MaterialPageRoute(
      builder: (context) => const PilihJemaatPage() 
    ));

    // Kalau Bos beneran milih orang (tidak pencet tombol back)
    if (selectedJemaat != null) {
      _showSetFamilyStatusDialog(selectedJemaat['id'], selectedJemaat['namaLengkap']);
    }
  }

  void _showSetFamilyStatusDialog(String jemaatId, String namaJemaat) {
    final List<String> statusOptions = ["Istri", "Anak"];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Pilih status untuk $namaJemaat", style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: statusOptions.map((status) => ListTile(
            title: Text(status),
            onTap: () {
              Navigator.pop(context);
              _addMemberToFamily(jemaatId, namaJemaat, status);
            },
          )).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
        ],
      ),
    );
  }

  Future<void> _addMemberToFamily(String jemaatId, String namaJemaat, String newStatus) async {
    if (_churchId == null) return;
    try {
      await _db.collection("churches").doc(_churchId).collection("jemaat").doc(jemaatId).update({
        "idKepalaKeluarga": widget.idKepalaKeluarga,
        "statusKeluarga": newStatus
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$namaJemaat berhasil ditambahkan sebagai $newStatus.")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal menambahkan anggota.")));
    }
  }

  void _showMemberActionDialog(Map<String, dynamic> anggota, String docId) {
    if (anggota['statusKeluarga'] == 'Kepala Keluarga') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tidak ada aksi untuk Kepala Keluarga.")));
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_remove, color: Colors.red),
              title: Text("Keluarkan ${anggota['namaLengkap']} dari Keluarga", style: const TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showRemoveMemberConfirmation(anggota, docId);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRemoveMemberConfirmation(Map<String, dynamic> anggota, String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Keluarkan Anggota"),
        content: Text("Yakin ingin mengeluarkan ${anggota['namaLengkap']} dari keluarga ini? Mereka akan menjadi 'Kepala Keluarga' untuk keluarga baru."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _removeMemberFromFamily(docId, anggota['namaLengkap']);
            },
            child: const Text("Ya, Keluarkan", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _removeMemberFromFamily(String docId, String nama) async {
    if (_churchId == null) return;
    try {
      await _db.collection("churches").doc(_churchId).collection("jemaat").doc(docId).update({
        "idKepalaKeluarga": docId, 
        "statusKeluarga": "Kepala Keluarga"
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$nama berhasil dikeluarkan.")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal melakukan aksi.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_churchId == null) return const Scaffold(body: Center(child: Text("Data gereja tidak valid.")));
    
    // 👇 AMBIL STATUS ADMIN UNTUK SATPAM 👇
    bool isAdmin = _userManager.isAdmin();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text("Keluarga ${widget.namaKepalaKeluarga}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection("churches").doc(_churchId).collection("jemaat")
            .where("idKepalaKeluarga", isEqualTo: widget.idKepalaKeluarga)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.indigo));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Tidak ada anggota keluarga."));
          }

          var listAnggota = snapshot.data!.docs.toList();
          listAnggota.sort((a, b) {
            var dataA = a.data() as Map<String, dynamic>;
            var dataB = b.data() as Map<String, dynamic>;
            return _getSortWeight(dataA['statusKeluarga']).compareTo(_getSortWeight(dataB['statusKeluarga']));
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: listAnggota.length,
            itemBuilder: (context, index) {
              var doc = listAnggota[index];
              var data = doc.data() as Map<String, dynamic>;
              data['id'] = doc.id; // Jangan lupa simpan ID-nya untuk dikirim ke detail
              
              String status = data['statusKeluarga'] ?? "-";
              String nama = data['namaLengkap'] ?? "Tanpa Nama";
              String? fotoUrl = data['fotoProfil'];
              
              bool isKepala = status == "Kepala Keluarga";

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: isKepala ? Colors.indigo.shade200 : Colors.transparent, width: 1.5)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    radius: 25,
                    backgroundColor: isKepala ? Colors.indigo : Colors.grey.shade200,
                    backgroundImage: fotoUrl != null ? CachedNetworkImageProvider(fotoUrl) : null,
                    child: fotoUrl == null ? Icon(Icons.person, color: isKepala ? Colors.white : Colors.grey) : null,
                  ),
                  title: Text(nama, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isKepala ? Colors.indigo.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      status, 
                      style: TextStyle(color: isKepala ? Colors.indigo.shade800 : Colors.orange.shade800, fontSize: 12, fontWeight: FontWeight.w600)
                    ),
                  ),
                  // 👇 HANYA ADMIN YANG BISA LIHAT TOMBOL TITIK TIGA INI 👇
                  trailing: isAdmin ? IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showMemberActionDialog(data, doc.id),
                  ) : null,
                  onTap: () {
                    // 👇 TOMBOL DETAIL SUDAH DISAMBUNG 👇
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => DetailJemaatPage(jemaatData: data)
                    ));
                  },
                ),
              );
            },
          );
        },
      ),
      // 👇 HANYA ADMIN YANG BISA LIHAT TOMBOL TAMBAH ANGGOTA INI 👇
      floatingActionButton: isAdmin ? FloatingActionButton.extended(
        onPressed: _showAddMemberOptionsDialog,
        backgroundColor: Colors.indigo,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Tambah Anggota", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ) : null,
    );
  }
}