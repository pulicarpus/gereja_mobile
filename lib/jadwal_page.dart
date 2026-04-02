import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_manager.dart';

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
    // Meniru UserManager di aplikasi lama
    churchId = UserManager().activeChurchId;
    isAdmin = UserManager().isAdmin();
  }

  @override
  Widget build(BuildContext context) {
    if (churchId == null) return const Scaffold(body: Center(child: Text("ID Gereja Kosong")));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(widget.filterKategorial ?? "Jadwal Ibadah"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('churches').doc(churchId).collection('jadwal')
            .orderBy('tanggal', descending: false).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          final docs = snapshot.data?.docs ?? [];
          final filteredDocs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final kat = data['kategoriKegiatan'];
            if (widget.filterKategorial == null || widget.filterKategorial!.isEmpty) {
              return kat == null || kat == "" || kat == "Umum";
            }
            return kat == widget.filterKategorial;
          }).toList();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredDocs.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return _buildPengumumanCard();
              final doc = filteredDocs[index - 1];
              return _buildJadwalItem(doc);
            },
          );
        },
      ),
      // FAB Tambah Jadwal (Hanya muncul jika Admin)
      floatingActionButton: isAdmin ? FloatingActionButton(
        onPressed: () => _navigasiTambahEdit(null),
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
  }

  // --- BAGIAN PENGUMUMAN (Bisa Klik Lama untuk Edit) ---
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
              color: const Color(0xFFFFF9C4),
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

  // --- BAGIAN JADWAL (Ada Tombol Susunan & Klik Lama) ---
  Widget _buildJadwalItem(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final pelayan = data['pelayan'] as Map<String, dynamic>? ?? {};
    
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

    final visibleRows = rows.where((r) => r['val'] != null && r['val'].toString().isNotEmpty).toList();

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
              ...List.generate(visibleRows.length, (index) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: index % 2 == 0 ? Colors.white : Colors.blue.shade50.withOpacity(0.3),
                  child: Row(
                    children: [
                      SizedBox(width: 110, child: Text(visibleRows[index]['label'], style: const TextStyle(color: Colors.grey, fontSize: 12))),
                      Expanded(child: Text(visibleRows[index]['val'].toString().replaceAll(", ", "\n"), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    ],
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text("Firman: ${data['deskripsi'] ?? '-'}", style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _navigasiSusunan(doc.id),
                          icon: const Icon(Icons.list_alt, size: 18),
                          label: const Text("Susunan Acara"),
                        ),
                        if (isAdmin) IconButton(onPressed: () => _navigasiTambahEdit(doc.id), icon: const Icon(Icons.edit, color: Colors.orange)),
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

  // --- FUNGSI LOGIKA (Meniru Kotlin) ---

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
          ListTile(leading: const Icon(Icons.edit), title: Text("Edit $nama"), onTap: () { Navigator.pop(context); _navigasiTambahEdit(id); }),
          ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("Hapus Jadwal"), onTap: () {
            Navigator.pop(context);
            _db.collection('churches').doc(churchId).collection('jadwal').doc(id).delete();
          }),
        ],
      ),
    );
  }

  void _navigasiSusunan(String jadwalId) {
    // Navigasi ke halaman SusunanAcaraActivity (Bos perlu buat file-nya)
    print("Membuka susunan acara untuk: $jadwalId");
  }

  void _navigasiTambahEdit(String? jadwalId) {
    // Navigasi ke halaman AddEditJadwal (Bos perlu buat file-nya)
    print("Edit/Tambah Jadwal: $jadwalId");
  }
}