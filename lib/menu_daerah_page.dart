import 'package:flutter/material.dart';
import 'dashboard_daerah_page.dart'; // Import dashboard statistik yang tadi

class MenuDaerahPage extends StatelessWidget {
  const MenuDaerahPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Pusat Kendali Daerah", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(25),
        crossAxisCount: 2, // 2 Kolom biar ikonnya besar dan jelas
        crossAxisSpacing: 15,
        mainAxisSpacing: 15,
        children: [
          _buildMenuSultan(context, Icons.church, "Data Gereja\n& Pengerja", Colors.blue, () {
            // Arahkan ke list gereja dan gembala
          }),
          _buildMenuSultan(context, Icons.account_balance_wallet, "Laporan\nKeuangan", Colors.green, () {
            // Arahkan ke gabungan keuangan daerah
          }),
          _buildMenuSultan(context, Icons.assignment_ind, "Badan\nPengurus", Colors.orange, () {
            // Arahkan ke daftar pengurus daerah
          }),
          _buildMenuSultan(context, Icons.analytics, "Dashboard\nStatistik", Colors.purple, () {
            // 👇 KE HALAMAN GRAFIK YANG KITA BUAT TADI 👇
            Navigator.push(context, MaterialPageRoute(builder: (c) => const DashboardDaerahPage()));
          }),
          _buildMenuSultan(context, Icons.notifications_active, "Info & Surat\nDaerah", Colors.red, () {
            // Menu tambahan untuk edaran daerah
          }),
          _buildMenuSultan(context, Icons.settings_suggest, "Pengaturan\nDaerah", Colors.grey, () {
            // Pengaturan khusus admin daerah
          }),
        ],
      ),
    );
  }

  Widget _buildMenuSultan(BuildContext context, IconData icon, String title, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
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
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 35, color: color),
            ),
            const SizedBox(height: 15),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}