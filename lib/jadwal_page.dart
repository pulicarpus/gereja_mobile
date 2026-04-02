import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Import file pendukung sesuai struktur folder di Acode
import 'user_manager.dart'; 
import 'add_edit_jadwal_page.dart';
import 'susunan_acara_page.dart';

class JadwalPage extends StatefulWidget {
  final String? filterKategorial;
  const JadwalPage({super.key, this.filterKategorial});

  @override
  State<JadwalPage> createState() => _JadwalPageState();
}

class _JadwalPageState extends State<JadwalPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? churchId;
  bool isAdmin = false;

  @override
  void initState() {
    super.initState();
    // Ambil data dari UserManager (seperti di Kotlin)
    churchId = UserManager().activeChurchId;
    isAdmin = UserManager().isAdmin();
  }

  @override
  Widget build(BuildContext context) {
    if (churchId == null) {
      return const Scaffold(body: Center(child: Text("ID Gereja tidak ditemukan")));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(widget.filterKategorial ?? "Jadwal Ibadah & Kegiatan"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Path sub-koleksi: churches -> {id} -> jadwal
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
          
          // Filter manual untuk memisahkan Umum vs Kategorial
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
              if (index == 0) return _buildPengumumanCard();
              final doc = filteredDocs[index - 1];
              return _buildJadwalCard(doc);
            },
          );
        },
      ),
      // Tombol Tambah Jadwal hanya muncul jika Admin
      floatingActionButton: isAdmin ? FloatingActionButton(
        onPressed: () => _navigasiTambahEdit(null),
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
  }

  // --- WIDGET PENGUMUMAN (KLIK LAMA UNTUK EDIT) ---
  Widget _buildPengumumanCard() {
    final docId = (widget.filterKategorial == null) ? "utama" : "pengumuman_${widget.filterKategorial}";
    
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('churches').doc(churchId).collection('pengumuman').doc(docId).snapshots(),
      builder: (context, snapshot) {
        String teks = snapshot.data?.get('teks') ?? "Belum ada pengumuman. Tekan lama untuk membuat.";
        
        return GestureDetector(
          onLongPress: isAdmin ? () => _showEditPengumumanDialog(docId, teks) : null,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9C4), // Kuning lembut
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.campaign, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text("PENGUMUMAN", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(teks, style: const TextStyle(fontSize: 14, color: Colors.black87)),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- WIDGET JADWAL (WARNA ZEBRA & TOMBOL SUSUNAN) ---
  Widget _buildJadwalCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final pelayan = data['pelayan'] as Map<String, dynamic>? ?? {};
    
    // Daftar pelayan sesuai Triple di Kotlin
    final List<Map<String, dynamic>> rows = [
      {'label': 'W.L', 'val': pelayan['Worship Leader']},
      {'label': 'Singer', 'val': pelayan['Singer']},
      {'label': 'Musik', 'val': pelayan['Pemain Musik']},
      {'label': 'Tamborin', 'val': pelayan['Pemain Tamborin']},
      {'label': 'LCD', 'val': pelayan['Operator LCD']},
      {'label': 'Kolektan', 'val': pelayan['Kolektan']},
      {'label': 'Doa Syafaat', 'val': pelayan['Doa Syafaat']},
      {'label': 'Penerima Tamu', 'val': pelayan['Penerima Tamu']},
    ];

    // Hanya tampilkan yang ada datanya (setupPelayanRow)
    final visibleRows = rows.where((r) => r['val'] != null && r['val'].toString().trim().isNotEmpty).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onLongPress: isAdmin ? () => _showEditDeleteDialog(doc.id, data['namaKegiatan']) : null,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: ExpansionTile(
            title: Text(data['namaKegiatan'] ?? "-", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${data['waktu'] ?? '-'} | ${data['tempat'] ?? '-'}", style: const TextStyle(fontSize: 12)),
            children: [
              // Looping baris pelayan dengan warna zebra
              ...List.generate(visibleRows.length, (index) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: index % 2 == 0 ? Colors.white : Colors.blue.shade50.withOpacity(0.3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 110, child: Text(visibleRows[index]['label'], style: const TextStyle(color: Colors.grey, fontSize: 12))),
                      Expanded(
                        child: Text(
                          visibleRows[index]['val'].toString().replaceAll(", ", "\n"),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text("Firman: ${data['deskripsi'] ?? '-'}", style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Tombol Susunan Acara
                        ElevatedButton.icon(
                          onPressed: () => _navigasiSusunan(doc.id),
                          icon: const Icon(Icons.list_alt, size: 18),
                          label: const Text("Susunan Acara"),
                        ),
                        if (isAdmin) IconButton(
                          onPressed: () => _navigasiTambahEdit(doc.id), 
                          icon: const Icon(Icons.edit, color: Colors.orange)
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- FUNGSI AKSI & NAVIGASI ---

  void _showEditPengumumanDialog(String docId, String currentText) {
    final controller = TextEditingController(text: currentText.contains("Belum ada") ? "" : currentText);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Update Pengumuman"),
        content: TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(hintText: "Tulis pengumuman...")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () {
              _db.collection('churches').doc(churchId).collection('pengumuman').doc(docId).set({
                'teks': controller.text,
                'waktuUpdate': Timestamp.now(),
                'kategori': widget.filterKategorial
              });
              Navigator.pop(context);
            },
            child: const Text("Simpan"),
          ),
        ],
      ),
    );
  }

  void _showEditDeleteDialog(String id, String nama) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit), 
            title: Text("Edit $nama"), 
            onTap: () { Navigator.pop(context); _navigasiTambahEdit(id); }
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red), 
            title: const Text("Hapus Jadwal"), 
            onTap: () {
              Navigator.pop(context);
              _db.collection('churches').doc(churchId).collection('jadwal').doc(id).delete();
            }
          ),
        ],
      ),
    );
  }

  void _navigasiSusunan(String jadwalId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SusunanAcaraPage(jadwalId: jadwalId)),
    );
  }

  void _navigasiTambahEdit(String? jadwalId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddEditJadwalPage(jadwalId: jadwalId, filterKategorial: widget.filterKategorial)),
    );
  }
}