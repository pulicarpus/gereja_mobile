import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'user_manager.dart';

class PilihJemaatPage extends StatefulWidget {
  const PilihJemaatPage({super.key});

  @override
  State<PilihJemaatPage> createState() => _PilihJemaatPageState();
}

class _PilihJemaatPageState extends State<PilihJemaatPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final UserManager _userManager = UserManager();
  String? _churchId;

  // 👇 VARIABEL UNTUK PENCARIAN 👇
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _churchId = _userManager.getChurchIdForCurrentView();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_churchId == null) return const Scaffold(body: Center(child: Text("Data gereja tidak valid")));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        // 👇 LOGIKA APPBAR BERUBAH JADI KOTAK PENCARIAN KALAU TOMBOL DITEKAN 👇
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Cari nama jemaat...",
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
              )
            : const Text("Pilih Jemaat", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // 👇 TOMBOL KACA PEMBESAR / SILANG 👇
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _searchQuery = "";
                } else {
                  _isSearching = true;
                }
              });
            },
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Mengambil semua jemaat di gereja ini
        stream: _db.collection("churches").doc(_churchId).collection("jemaat").orderBy("namaLengkap").snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.indigo));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Belum ada data jemaat."));
          }

          // 👇 PROSES PENYARINGAN DATA BERDASARKAN KATA KUNCI 👇
          var listJemaat = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            String nama = (data['namaLengkap'] ?? "").toLowerCase();
            return nama.contains(_searchQuery);
          }).toList();

          // Kalau hasil pencarian kosong
          if (listJemaat.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 60, color: Colors.grey.shade400),
                  const SizedBox(height: 10),
                  Text("Tidak ada jemaat bernama '$_searchQuery'", style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: listJemaat.length,
            itemBuilder: (context, index) {
              var doc = listJemaat[index];
              var data = doc.data() as Map<String, dynamic>;
              
              // Tambahkan ID dokumen ke dalam map data supaya gampang dipakai nanti
              data['id'] = doc.id; 

              String nama = data['namaLengkap'] ?? "Tanpa Nama";
              String? fotoUrl = data['fotoProfil'];
              String statusKeluarga = data['statusKeluarga'] ?? "Belum terikat keluarga";

              return Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.shade100,
                    backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty ? CachedNetworkImageProvider(fotoUrl) : null,
                    child: fotoUrl == null || fotoUrl.isEmpty ? const Icon(Icons.person, color: Colors.indigo) : null,
                  ),
                  title: Text(nama, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(statusKeluarga, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  trailing: const Icon(Icons.person_add, color: Colors.green),
                  onTap: () {
                    // Saat diklik, tutup halaman dan bawa datanya kembali
                    Navigator.pop(context, data);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}