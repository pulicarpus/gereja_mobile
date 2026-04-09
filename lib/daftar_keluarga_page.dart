import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_manager.dart';
import 'anggota_keluarga_page.dart'; // Memanggil halaman yang kita buat kemarin

class DaftarKeluargaPage extends StatefulWidget {
  const DaftarKeluargaPage({super.key});

  @override
  State<DaftarKeluargaPage> createState() => _DaftarKeluargaPageState();
}

class _DaftarKeluargaPageState extends State<DaftarKeluargaPage> {
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
        title: const Text("Daftar Keluarga", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // 👇 KITA HANYA MENGAMBIL YANG STATUSNYA KEPALA KELUARGA 👇
        stream: _db.collection("churches").doc(_churchId).collection("jemaat")
            .where("statusKeluarga", isEqualTo: "Kepala Keluarga")
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.indigo));
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.family_restroom, size: 60, color: Colors.grey),
                  SizedBox(height: 16),
                  Text("Belum ada data keluarga.", style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          // Urutkan berdasarkan Abjad Nama Keluarga
          var listKeluarga = snapshot.data!.docs.toList();
          listKeluarga.sort((a, b) {
            var dataA = a.data() as Map<String, dynamic>;
            var dataB = b.data() as Map<String, dynamic>;
            String namaA = dataA['namaLengkap'] ?? "";
            String namaB = dataB['namaLengkap'] ?? "";
            return namaA.toLowerCase().compareTo(namaB.toLowerCase());
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: listKeluarga.length,
            itemBuilder: (context, index) {
              var doc = listKeluarga[index];
              var data = doc.data() as Map<String, dynamic>;
              
              String nama = data['namaLengkap'] ?? "Tanpa Nama";
              String alamat = data['alamat'] ?? "Alamat belum diisi";

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  leading: CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.indigo.shade100,
                    child: const Icon(Icons.family_restroom, color: Colors.indigo),
                  ),
                  title: Text("Kel. $nama", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text(alamat, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                  onTap: () {
                    // 👇 LOMPAT KE HALAMAN ANGGOTA KELUARGA 👇
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AnggotaKeluargaPage(
                          idKepalaKeluarga: doc.id, // ID dia sebagai patokan pencarian anggota
                          namaKepalaKeluarga: nama,
                        ),
                      ),
                    );
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