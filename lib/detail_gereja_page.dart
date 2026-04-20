import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DetailGerejaPage extends StatelessWidget {
  final String churchId;
  final String namaGereja;

  const DetailGerejaPage({super.key, required this.churchId, required this.namaGereja});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text("Statistik $namaGereja", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // 👇 FOKUS MENGHITUNG DATA JEMAAT DI GEREJA YANG DIKLIK SAJA 👇
        stream: FirebaseFirestore.instance.collection('churches').doc(churchId).collection('jemaat').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text("Belum ada data jemaat di gereja ini.", style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          // Variabel Penampung Hitungan
          int totalJemaat = snapshot.data!.docs.length;
          int totalKK = 0;
          int pria = 0;
          int wanita = 0;
          int sudahBaptis = 0;
          int blmBaptis = 0;

          // Hitungan Kategorial
          Map<String, int> kategorialCount = {};

          // Mesin Penghitung
          for (var doc in snapshot.data!.docs) {
            var data = doc.data() as Map<String, dynamic>;

            // 1. Hitung Gender
            String jk = (data['jenisKelamin'] ?? "").toString().toLowerCase();
            if (jk == 'laki-laki' || jk == 'pria' || jk == 'l') pria++;
            else if (jk == 'perempuan' || jk == 'wanita' || jk == 'p') wanita++;

            // 2. Hitung Kepala Keluarga (KK)
            String statusKel = (data['statusKeluarga'] ?? data['hubunganKeluarga'] ?? "").toString().toLowerCase();
            if (statusKel.contains('kepala')) totalKK++;

            // 3. Hitung Baptis
            String baptis = (data['statusBaptis'] ?? "").toString().toLowerCase();
            if (baptis == 'sudah' || baptis == 'ya') sudahBaptis++;
            else blmBaptis++;

            // 4. Hitung Kategorial
            String kategorial = data['kategorial'] ?? "Belum Diatur";
            if (kategorial.trim().isEmpty) kategorial = "Belum Diatur";
            kategorialCount[kategorial] = (kategorialCount[kategorial] ?? 0) + 1;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // KARTU UTAMA (Jemaat & KK)
                Row(
                  children: [
                    Expanded(child: _buildStatCard(Icons.people, "Total Jemaat", totalJemaat.toString(), Colors.blue)),
                    const SizedBox(width: 15),
                    Expanded(child: _buildStatCard(Icons.family_restroom, "Total KK", totalKK.toString(), Colors.orange)),
                  ],
                ),
                const SizedBox(height: 15),

                // KARTU GENDER & BAPTISAN
                Row(
                  children: [
                    Expanded(child: _buildStatCard(Icons.male, "Pria", pria.toString(), Colors.cyan)),
                    const SizedBox(width: 15),
                    Expanded(child: _buildStatCard(Icons.female, "Wanita", wanita.toString(), Colors.pink)),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(child: _buildStatCard(Icons.water_drop, "Sdh Baptis", sudahBaptis.toString(), Colors.teal)),
                    const SizedBox(width: 15),
                    Expanded(child: _buildStatCard(Icons.water_drop_outlined, "Blm Baptis", blmBaptis.toString(), Colors.grey.shade600)),
                  ],
                ),

                const SizedBox(height: 30),
                const Text("Sebaran Kategorial", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                const SizedBox(height: 15),

                // LIST KATEGORIAL
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: kategorialCount.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      String key = kategorialCount.keys.elementAt(index);
                      int val = kategorialCount[key]!;
                      return ListTile(
                        leading: const Icon(Icons.category, color: Colors.indigo),
                        title: Text(key, style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(20)),
                          child: Text("$val Jiwa", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                        ),
                      );
                    },
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 15),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}