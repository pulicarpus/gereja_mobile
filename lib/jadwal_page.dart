import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_manager.dart'; // Pastikan Bos sudah buat class ini untuk ambil churchId

class JadwalPage extends StatefulWidget {
  final String? filterKategorial;
  const JadwalPage({super.key, this.filterKategorial});

  @override
  State<JadwalPage> createState() => _JadwalPageState();
}

class _JadwalPageState extends State<JadwalPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? churchId;

  @override
  void initState() {
    super.initState();
    // Meniru UserManager.getChurchIdForCurrentView() di Kotlin
    churchId = UserManager().activeChurchId; 
  }

  @override
  Widget build(BuildContext context) {
    if (churchId == null) {
      return const Scaffold(body: Center(child: Text("ID Gereja Kosong")));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(widget.filterKategorial ?? "Jadwal Ibadah"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Path sesuai kode Kotlin: churches -> {id} -> jadwal
        stream: _db.collection('churches')
            .doc(churchId)
            .collection('jadwal')
            .orderBy('tanggal', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data!.docs;
          
          // Filter manual meniru logika Kotlin loadData()
          final filteredDocs = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final kategori = data['kategoriKegiatan'];
            if (widget.filterKategorial == null || widget.filterKategorial!.isEmpty) {
              return kategori == null || kategori == "" || kategori == "Umum";
            }
            return kategori == widget.filterKategorial;
          }).toList();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredDocs.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return _buildPengumumanSection();
              
              final data = filteredDocs[index - 1].data() as Map<String, dynamic>;
              return _buildJadwalItem(data);
            },
          );
        },
      ),
    );
  }

  Widget _buildJadwalItem(Map<String, dynamic> data) {
    final Map<String, dynamic> pelayan = data['pelayan'] ?? {};
    
    // Daftar pelayan sesuai Triple di kode Kotlin
    final List<Map<String, dynamic>> rows = [
      {'label': 'W.L', 'data': pelayan['Worship Leader']},
      {'label': 'Singer', 'data': pelayan['Singer']},
      {'label': 'Musik', 'data': pelayan['Pemain Musik']},
      {'label': 'Tamborin', 'data': pelayan['Pemain Tamborin']},
      {'label': 'LCD', 'data': pelayan['Operator LCD']},
      {'label': 'Kolektan', 'data': pelayan['Kolektan']},
      {'label': 'Doa Syafaat', 'data': pelayan['Doa Syafaat']},
      {'label': 'Penerima Tamu', 'data': pelayan['Penerima Tamu']},
    ];

    // Filter baris yang tidak kosong (setupPelayanRow di Kotlin)
    final visibleRows = rows.where((row) => 
      row['data'] != null && row['data'].toString().trim().isNotEmpty
    ).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: ExpansionTile(
        title: Text(data['namaKegiatan'] ?? "-", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${data['waktu'] ?? '-'} | ${data['tempat'] ?? '-'}", style: const TextStyle(fontSize: 12)),
        children: [
          const Divider(height: 1),
          // Bagian Detail Pelayan dengan warna Zebra (visibleRowIndex)
          ...List.generate(visibleRows.length, (index) {
            final row = visibleRows[index];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              // Warna zebra: Row background even vs odd
              color: index % 2 == 0 ? Colors.white : Colors.blue.shade50.withOpacity(0.3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 110, child: Text(row['label'], style: const TextStyle(color: Colors.grey, fontSize: 13))),
                  Expanded(
                    child: Text(
                      // Replace koma dengan baris baru (regex di Kotlin)
                      row['data'].toString().trim().replaceAll(RegExp(r',\s*'), '\n'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          }),
          // Bagian Deskripsi/Firman
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text("Firman: ${data['deskripsi'] ?? '-'}", style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.blueGrey)),
          ),
        ],
      ),
    );
  }

  Widget _buildPengumumanSection() {
    final docId = (widget.filterKategorial == null) ? "utama" : "pengumuman_${widget.filterKategorial}";
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('churches').doc(churchId).collection('pengumuman').doc(docId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.yellow.shade100, borderRadius: BorderRadius.circular(8)),
          child: Text(snapshot.data!['teks'] ?? "", style: const TextStyle(fontSize: 13)),
        );
      },
    );
  }
}