import 'package:flutter/material.dart';

// --- IMPORT SEMUA HALAMAN TERKAIT ---
import 'gallery_page.dart';
import 'laporan_transaksi_page.dart';
import 'data_jemaat_page.dart';
import 'chatroom_page.dart'; 
import 'jadwal_page.dart';      

// 👇 IMPORT SANG SATPAM (USER MANAGER) 👇
import 'user_manager.dart';

class SubKategorialPage extends StatelessWidget {
  final String namaKomisi;

  const SubKategorialPage({super.key, required this.namaKomisi});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("Pelayanan $namaKomisi"),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // --- HEADER INFO (WIDGET ATAS) ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05), 
                    blurRadius: 10, 
                    offset: const Offset(0, 5)
                  )
                ],
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFF075E54).withOpacity(0.1),
                    child: const Icon(Icons.account_balance, size: 35, color: Color(0xFF075E54)),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    "Pusat Informasi $namaKomisi",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    "Kelola data anggota, chat grup, jadwal kegiatan, dan kas keuangan kategorial Anda.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),

            // --- GRID MENU (PENGHUBUNG SEMUA TOMBOL) ---
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1.1, 
              children: [
                // 1. DATA ANGGOTA 
                _buildMenuCard(
                  context,
                  "Data Anggota",
                  Icons.people_alt_rounded,
                  Colors.blue,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DataJemaatPage(filterKategorial: namaKomisi),
                    ),
                  ),
                ),

                // 2. CHAT GROUP (SATPAM DIAKTIFKAN DI SINI 🔒)
                _buildMenuCard(
                  context,
                  "Chat Group",
                  Icons.chat_bubble_rounded,
                  Colors.green,
                  () {
                    // Ambil buku panduan data jemaat
                    final userManager = UserManager();
                    bool isAdmin = userManager.isAdmin();
                    String komisiJemaat = userManager.userKomisi ?? "Umum";

                    // Cek apakah dia Admin/Superadmin ATAU anggota komisi yang sesuai
                    if (isAdmin || komisiJemaat == namaKomisi) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatroomPage(filterKategorial: namaKomisi),
                        ),
                      );
                    } else {
                      // Kalau nyasar, tolak dengan halus
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Maaf, Chat Group ini khusus internal anggota $namaKomisi."),
                          backgroundColor: Colors.redAccent,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),

                // 3. KEGIATAN 
                _buildMenuCard(
                  context,
                  "Kegiatan",
                  Icons.event_available_rounded,
                  Colors.orange,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => JadwalPage(filterKategorial: namaKomisi),
                    ),
                  ),
                ),

                // 4. KEUANGAN 
                _buildMenuCard(
                  context,
                  "Keuangan",
                  Icons.account_balance_wallet_rounded,
                  Colors.redAccent,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LaporanTransaksiPage(filterKategorial: namaKomisi),
                    ),
                  ),
                ),

                // 5. GALERI FOTO 
                _buildMenuCard(
                  context,
                  "Galeri Foto",
                  Icons.photo_library_rounded,
                  Colors.purple,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GalleryPage(filterKategorial: namaKomisi),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // --- WIDGET HELPER UNTUK MEMBUAT KARTU MENU ---
  Widget _buildMenuCard(BuildContext context, String label, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        splashColor: color.withOpacity(0.1),
        highlightColor: color.withOpacity(0.05),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              label, 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)
            ),
          ],
        ),
      ),
    );
  }
}