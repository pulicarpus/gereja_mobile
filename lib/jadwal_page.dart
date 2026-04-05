import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
        backgroundColor: Colors.indigo[900], 
        foregroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('churches').doc(churchId).collection('jadwal')
            .orderBy('tanggal', descending: false).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
             return const Center(child: Text("Terjadi kesalahan koneksi."));
          }
          
          final docs = snapshot.data?.docs ?? [];
          final filteredDocs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final kat = data['kategoriKegiatan'];
            if (widget.filterKategorial == null || widget.filterKategorial!.isEmpty) {
              return kat == null || kat == "" || kat == "Umum";
            }
            return kat == widget.filterKategorial;
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildPengumumanCard(),
              const SizedBox(height: 8),
              
              if (filteredDocs.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 50),
                  child: Center(
                    child: Text(
                      "Belum ada jadwal ibadah", 
                      style: TextStyle(color: Colors.grey, fontSize: 16)
                    )
                  ),
                )
              else
                ...filteredDocs.map((doc) => _buildJadwalCard(doc)),
            ],
          );
        },
      ),
      floatingActionButton: isAdmin ? FloatingActionButton(
        onPressed: () => _navigasiTambahEdit(null),
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
  }

  Widget _buildPengumumanCard() {
    final docId = (widget.filterKategorial == null) ? "utama" : "pengumuman_${widget.filterKategorial}";
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('churches').doc(churchId).collection('pengumuman').doc(docId).snapshots(),
      builder: (context, snapshot) {
        String teks = snapshot.data?.get('teks') ?? "Tidak ada pengumuman khusus.";
        return GestureDetector(
          onLongPress: isAdmin ? () => _showEditPengumumanDialog(docId, teks) : null,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9C4), 
              borderRadius: BorderRadius.circular(12), 
              border: Border.all(color: Colors.orange.shade300, width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
              ]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.campaign, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text("Pengumuman", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800])),
                  ],
                ),
                const SizedBox(height: 8),
                Text(teks, style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildJadwalCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final pelayan = data['pelayan'] as Map<String, dynamic>? ?? {};
    final String namaKeg = data['namaKegiatan'] ?? "-";
    
    // ==== PERBAIKAN: SEMUA PELAYAN SUDAH MASUK ====
    final List<Map<String, dynamic>> rows = [
      {'label': 'W.L', 'val': pelayan['Worship Leader']},
      {'label': 'Singer', 'val': pelayan['Singer']},
      {'label': 'Musik', 'val': pelayan['Pemain Musik']},
      // Mendukung baca data lama ('Tamborin') maupun baru ('Pemain Tamborin')
      {'label': 'Tamborin', 'val': pelayan['Pemain Tamborin'] ?? pelayan['Tamborin']}, 
      {'label': 'Operator LCD', 'val': pelayan['Operator LCD']},
      {'label': 'Kolektan', 'val': pelayan['Kolektan']},
      {'label': 'Doa Syafaat', 'val': pelayan['Doa Syafaat']},
      {'label': 'Penerima Tamu', 'val': pelayan['Penerima Tamu']},
    ];
    // ==============================================

    final visibleRows = rows.where((r) => r['val'] != null && r['val'].toString().trim().isNotEmpty).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onLongPress: isAdmin ? () => _showEditDeleteDialog(doc.id, namaKeg) : null,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.circular(12), 
            border: Border.all(color: Colors.indigo.shade100),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
            ]
          ),
          child: ExpansionTile(
            title: Text(namaKeg, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "${data['waktu'] ?? '-'} \n📍 ${data['tempat'] ?? '-'}",
                style: TextStyle(color: Colors.grey[700], height: 1.3),
              ),
            ),
            children: [
              const Divider(height: 1),
              ...List.generate(visibleRows.length, (index) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: index % 2 == 0 ? Colors.white : Colors.indigo.shade50.withOpacity(0.3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 105, child: Text(visibleRows[index]['label'], style: const TextStyle(color: Colors.grey))),
                      Expanded(child: Text(visibleRows[index]['val'].toString().replaceAll(", ", "\n"), style: const TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (data['deskripsi'] != null && data['deskripsi'].toString().trim().isNotEmpty) ...[
                       Text("Firman Tuhan:", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                       const SizedBox(height: 4),
                       Text("${data['deskripsi']}", style: const TextStyle(fontStyle: FontStyle.italic)),
                       const SizedBox(height: 16),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _navigasiSusunan(doc.id, namaKeg),
                          icon: const Icon(Icons.list_alt),
                          label: const Text("Susunan Acara"),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                        ),
                        if (isAdmin) 
                          OutlinedButton.icon(
                            onPressed: () => _navigasiTambahEdit(doc.id), 
                            icon: const Icon(Icons.edit, color: Colors.orange),
                            label: const Text("Edit", style: TextStyle(color: Colors.orange)),
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

  void _showEditPengumumanDialog(String docId, String currentText) {
    final controller = TextEditingController(text: currentText);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Update Pengumuman", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller, 
          maxLines: 4,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            hintText: "Ketik pengumuman di sini..."
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            onPressed: () {
              _db.collection('churches').doc(churchId).collection('pengumuman').doc(docId).set({'teks': controller.text});
              Navigator.pop(context);
            }, 
            child: const Text("Simpan")
          ),
        ],
      ),
    );
  }

  void _showEditDeleteDialog(String id, String nama) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text("Kelola: $nama", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.orange), 
            title: const Text("Edit Jadwal"), 
            onTap: () { Navigator.pop(context); _navigasiTambahEdit(id); }
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red), 
            title: const Text("Hapus Jadwal", style: TextStyle(color: Colors.red)), 
            onTap: () {
               Navigator.pop(context);
               showDialog(
                 context: context,
                 builder: (c) => AlertDialog(
                   title: const Text("Hapus Jadwal?"),
                   content: Text("Jadwal '$nama' akan dihapus permanen."),
                   actions: [
                     TextButton(onPressed: () => Navigator.pop(c), child: const Text("Batal")),
                     ElevatedButton(
                       style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                       onPressed: () {
                         _db.collection('churches').doc(churchId).collection('jadwal').doc(id).delete();
                         Navigator.pop(c);
                       }, 
                       child: const Text("Hapus", style: TextStyle(color: Colors.white))
                     )
                   ]
                 )
               );
            }
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _navigasiSusunan(String jadwalId, String namaKegiatan) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => SusunanAcaraPage(jadwalId: jadwalId, namaKegiatan: namaKegiatan)));
  }

  void _navigasiTambahEdit(String? jadwalId) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => AddEditJadwalPage(jadwalId: jadwalId, filterKategorial: widget.filterKategorial)));
  }
}