import 'package:flutter/material.dart';

// Import halaman-halaman yang sudah kita buat sebelumnya
import 'gallery_page.dart';
import 'laporan_transaksi_page.dart';
import 'data_jemaat_page.dart'; // Nanti sesuaikan namanya
import 'chatroom_page.dart';    // Nanti sesuaikan namanya
import 'jadwal_page.dart';      // Nanti sesuaikan namanya

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
            // Header Info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
              ),
              child: Column(
                children: [
                  Icon(Icons.account_balance, size: 50, color: Colors.teal),
                  const SizedBox(height: 10),
                  Text(
                    "Pusat Informasi $namaKomisi",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const Text("Kelola data, kegiatan, dan keuangan di sini.",
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // GRID MENU - PERSIS LOGIKA KOTLIN BOS
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              children: [
                _buildMenu(
                  context,
                  "Data Anggota",
                  Icons.people,
                  Colors.blue,
                  () => _bukaHalaman(context, "Data Anggota"),
                ),
                _buildMenu(
                  context,
                  "Chat Group",
                  Icons.chat,
                  Colors.green,
                  () => _bukaHalaman(context, "Chat"),
                ),
                _buildMenu(
                  context,
                  "Kegiatan",
                  Icons.event,
                  Colors.orange,
                  () => _bukaHalaman(context, "Kegiatan"),
                ),
                _buildMenu(
                  context,
                  "Keuangan",
                  Icons.account_balance_wallet,
                  Colors.red,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LaporanTransaksiPage(
                        filterKategorial: namaKomisi,
                      ),
                    ),
                  ),
                ),
                _buildMenu(
                  context,
                  "Galeri Foto",
                  Icons.photo_library,
                  Colors.purple,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GalleryPage(
                        filterKategorial: namaKomisi,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context, String label, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _bukaHalaman(BuildContext context, String tipe) {
    // ScaffoldMessenger untuk sementara sebelum halaman lainnya disambungkan
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Membuka $tipe $namaKomisi...")),
    );
  }
}