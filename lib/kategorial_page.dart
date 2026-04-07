import 'package:flutter/material.dart';
import 'sub_kategorial_page.dart'; // Nanti kita buat file ini

class KategorialPage extends StatelessWidget {
  const KategorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Kategorial & Komisi"),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2, // 2 Kolom seperti menu modern
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          children: [
            _buildMenuCard(
              context,
              "Sekolah Minggu",
              Icons.child_care,
              Colors.orange,
            ),
            _buildMenuCard(
              context,
              "Pemuda Remaja",
              Icons.group,
              Colors.blue,
            ),
            _buildMenuCard(
              context,
              "Perkawan",
              Icons.woman,
              Colors.pink,
            ),
            _buildMenuCard(
              context,
              "Perkaria",
              Icons.man,
              Colors.indigo,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(BuildContext context, String nama, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => _bukaSub(context, nama), // Persis fungsi bukaSub di Kotlin
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              nama,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _bukaSub(BuildContext context, String nama) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SubKategorialPage(namaKomisi: nama),
      ),
    );
  }
}