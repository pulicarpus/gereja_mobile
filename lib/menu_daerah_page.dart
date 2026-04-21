import 'package:flutter/material.dart';
import 'data_gereja_daerah_page.dart';
import 'dashboard_daerah_page.dart';
import 'keuangan_daerah_page.dart';

class MenuDaerahPage extends StatelessWidget {
  final String namaDaerah; // 👈 MENERIMA NAMA DAERAH DARI HALAMAN SEBELUMNYA

  const MenuDaerahPage({super.key, required this.namaDaerah});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text("Pusat Kendali - $namaDaerah", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Banner Daerah Dynamic
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.indigo.shade900, Colors.blue.shade800],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.account_balance, size: 60, color: Colors.white),
                  const SizedBox(height: 15),
                  Text(
                    "PENGURUS ${namaDaerah.toUpperCase()}", // 👈 NAMA DAERAH OTOMATIS BERUBAH
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    "Sistem Manajemen Multi-Gereja",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            // Grid Menu Daerah
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(25),
              crossAxisCount: 2, 
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              children: [
                _buildMenuSultan(context, Icons.church, "Data Gereja\n& Pengerja", Colors.blue, () {
                  // 👇 MASUK KE DAFTAR GEREJA KHUSUS DAERAH INI 👇
                  Navigator.push(context, MaterialPageRoute(builder: (c) => DataGerejaDaerahPage(namaDaerah: namaDaerah)));
                }),
                _buildMenuSultan(context, Icons.analytics, "Dashboard\nStatistik", Colors.purple, () {
                  // 👇 TAMBAHKAN KODE namaDaerah: namaDaerah DI SINI 👇
                  Navigator.push(context, MaterialPageRoute(builder: (c) => DashboardDaerahPage(namaDaerah: namaDaerah)));
                }),
                _buildMenuSultan(context, Icons.account_balance_wallet, "Laporan\nKeuangan", Colors.green, () {
                  // 👇 UBAH JADI SEPERTI INI 👇
                  Navigator.push(context, MaterialPageRoute(builder: (c) => KeuanganDaerahPage(namaDaerah: namaDaerah)));
                }),
                _buildMenuSultan(context, Icons.assignment_ind, "Badan\nPengurus", Colors.orange, () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Pengurus $namaDaerah segera hadir")));
                }),
                _buildMenuSultan(context, Icons.notifications_active, "Info & Surat\nDaerah", Colors.red, () {
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Surat $namaDaerah segera hadir")));
                }),
                _buildMenuSultan(context, Icons.settings_suggest, "Pengaturan\nDaerah", Colors.grey.shade700, () {
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Pengaturan $namaDaerah")));
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuSultan(BuildContext context, IconData icon, String title, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(25),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 35, color: color),
            ),
            const SizedBox(height: 15),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}