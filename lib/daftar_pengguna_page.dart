import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_manager.dart';
import 'detail_pengguna_page.dart';

class DaftarPenggunaPage extends StatefulWidget {
  const DaftarPenggunaPage({super.key});

  @override
  State<DaftarPenggunaPage> createState() => _DaftarPenggunaPageState();
}

class _DaftarPenggunaPageState extends State<DaftarPenggunaPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final UserManager _userManager = UserManager();

  @override
  Widget build(BuildContext context) {
    // 👇 LOGIKA KEAMANAN SULTAN: Ikuti Gereja yang sedang dipantau 👇
    String? activeChurchId = _userManager.getChurchIdForCurrentView();

    Query query = _db.collection("users");
    if (activeChurchId != null && activeChurchId.isNotEmpty) {
      // Admin akan melihat gerejanya sendiri.
      // Superadmin akan melihat gereja sesuai "Mode Pantau" yang sedang aktif.
      query = query.where("churchId", isEqualTo: activeChurchId);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Latar belakang abu-abu elegan
      appBar: AppBar(
        title: const Text("Manajemen Pengguna", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.indigo));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.group_off, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text("Belum ada data pengguna di gereja ini.", style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                ],
              ),
            );
          }

          var users = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            itemBuilder: (context, index) {
              var data = users[index].data() as Map<String, dynamic>;
              String docId = users[index].id;
              
              String nama = data['nama'] ?? "Tanpa Nama";
              String email = data['email'] ?? "Tidak ada email";
              String role = data['role'] ?? "user";
              String kelompok = data['kelompok'] ?? "Umum / Belum diatur";

              // Tentukan warna ikon berdasarkan pangkat
              Color avatarBgColor;
              Color avatarIconColor;
              IconData avatarIcon;

              if (role == 'superadmin') {
                avatarBgColor = Colors.red.shade50;
                avatarIconColor = Colors.red;
                avatarIcon = Icons.security;
              } else if (role == 'admin') {
                avatarBgColor = Colors.orange.shade50;
                avatarIconColor = Colors.orange;
                avatarIcon = Icons.admin_panel_settings;
              } else {
                avatarBgColor = Colors.indigo.shade50;
                avatarIconColor = Colors.indigo;
                avatarIcon = Icons.person;
              }

              return Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => DetailPenggunaPage(userId: docId)
                    ));
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: avatarBgColor,
                          child: Icon(avatarIcon, color: avatarIconColor),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(nama, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 2),
                              Text(email, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(5)),
                                    child: Text(role.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(kelompok, style: const TextStyle(fontSize: 11, color: Colors.purple, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}