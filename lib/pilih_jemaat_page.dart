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

  @override
  void initState() {
    super.initState();
    _churchId = _userManager.getChurchIdForCurrentView();
  }

  @override
  Widget build(BuildContext context) {
    if (_churchId == null) return const Scaffold(body: Center(child: Text("Data gereja tidak valid")));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Pilih Jemaat", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
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

          var listJemaat = snapshot.data!.docs;

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
                    backgroundImage: fotoUrl != null ? CachedNetworkImageProvider(fotoUrl) : null,
                    child: fotoUrl == null ? const Icon(Icons.person, color: Colors.indigo) : null,
                  ),
                  title: Text(nama, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(statusKeluarga, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  trailing: const Icon(Icons.person_add, color: Colors.green),
                  onTap: () {
                    // 👇 INI KUNCINYA: Saat diklik, tutup halaman dan bawa datanya kembali!
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