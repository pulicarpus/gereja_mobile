import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class JadwalPage extends StatefulWidget {
  const JadwalPage({super.key});

  @override
  State<JadwalPage> createState() => _JadwalPageState();
}

class _JadwalPageState extends State<JadwalPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Jadwal Ibadah & Kegiatan"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Mengikuti alur aplikasi lama, asumsikan koleksi bernama 'schedules' atau 'jadwal'
        // Silakan ganti 'schedules' jika nama koleksinya berbeda di Firestore Bos
        stream: _db.collection('schedules').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Gagal memuat data"));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length + 1, // +1 untuk header pengumuman
            itemBuilder: (context, index) {
              if (index == 0) return _buildAnnouncementCard();
              
              final data = docs[index - 1].data() as Map<String, dynamic>;
              return _buildJadwalCard(data);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {}, // Logika tambah jadwal
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildAnnouncementCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit, color: Colors.green.shade700, size: 16),
              const SizedBox(width: 8),
              Text("PENGUMUMAN TERBARU", 
                style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          const Text("Jangan Lupa besok ibadah, di gereja", style: TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildJadwalCard(Map<String, dynamic> data) {
    // Mapping data sesuai file Kotlin 'JadwalAdapter' yang Bos kirim
    final String namaKegiatan = data['namaKegiatan'] ?? "-";
    final String waktu = data['waktu'] ?? "-";
    final String tempat = data['tempat'] ?? "-";
    final String firman = data['deskripsi'] ?? "-"; // Di Kotlin: tvValueFirman = jadwal.deskripsi
    
    // Ambil Map 'pelayan'
    final Map<String, dynamic> pelayan = data['pelayan'] ?? {};

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderRow("Nama kegiatan", namaKegiatan),
                _buildHeaderRow("Tanggal/Waktu", waktu),
                _buildHeaderRow("Tempat", tempat),
                _buildHeaderRow("Firman Tuhan", firman),
                
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () {}, child: const Text("Lihat Pelayan", style: TextStyle(color: Colors.blue))),
                    TextButton(onPressed: () {}, child: const Text("Susunan Acara", style: TextStyle(color: Colors.blue))),
                  ],
                ),
              ],
            ),
          ),
          
          // Bagian Detail Pelayan (Zebra Row seperti di Kotlin)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50.withOpacity(0.3),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Column(
              children: [
                _buildPelayanRow("W.L", pelayan['Worship Leader'], true),
                _buildPelayanRow("Singer", pelayan['Singer'], false),
                _buildPelayanRow("Musik", pelayan['Pemain Musik'], true),
                _buildPelayanRow("Tamborin", pelayan['Pemain Tamborin'], false),
                _buildPelayanRow("LCD", pelayan['Operator LCD'], true),
                _buildPelayanRow("Kolektan", pelayan['Kolektan'], false),
                _buildPelayanRow("Doa Syafaat", pelayan['Doa Syafaat'], true),
                _buildPelayanRow("Penerima Tamu", pelayan['Penerima Tamu'], false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text("$label :", style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: Colors.black87))),
        ],
      ),
    );
  }

  Widget _buildPelayanRow(String label, dynamic data, bool isEven) {
    // Jika data kosong, sembunyikan baris (sesuai fungsi setupPelayanRow di Kotlin)
    if (data == null || data.toString().trim().isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      // Warna Zebra (Even/Odd)
      color: isEven ? Colors.white : Colors.blue.shade50.withOpacity(0.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(
            child: Text(
              data.toString().replaceAll(", ", "\n"), // Replace koma dengan baris baru seperti di Kotlin
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}