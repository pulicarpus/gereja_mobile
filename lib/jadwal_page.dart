import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; 
import 'package:http/http.dart' as http; // 👈 IMPORT KURIR HTTP
import 'dart:convert'; // 👈 IMPORT KONVERTER

import 'user_manager.dart'; 
import 'add_edit_jadwal_page.dart';
import 'susunan_acara_page.dart';
import 'secrets.dart'; // 👈 IMPORT BRANKAS RAHASIA UNTUK KUNCI ONESIGNAL

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

  String _formatTanggalSultan(String rawDate) {
    try {
      DateTime dt = DateFormat("yyyy-MM-dd HH:mm").parse(rawDate);
      return DateFormat("EEEE, d MMMM yyyy • HH:mm", "id_ID").format(dt);
    } catch (e) {
      return rawDate; 
    }
  }

  // 👇 --- MANTRA ONESIGNAL DENGAN TIKET KE HALAMAN JADWAL --- 👇
  Future<void> _sendPengumumanNotification(String isiPengumuman) async {
    try {
      Map<String, dynamic> payload = {
        "app_id": "a9ff250a-56ef-413d-b825-67288008d614", // ID OneSignal Bos
        "included_segments": ["All"], // Tembak ke semua jemaat
        "headings": {"en": "📢 Pengumuman Gereja!"},
        "contents": {"en": isiPengumuman},
        // 👇 INI DIA TIKET MENUJU HALAMAN JADWAL 👇
        "data": {
          "type": "jadwal",
          "kategorial": widget.filterKategorial // Ikut bawa nama kategorial kalau ada
        }
      };

      await http.post(
        Uri.parse("https://onesignal.com/api/v1/notifications"),
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Authorization": "Basic $osRestKeySecret" // Pakai kunci dari GitHub Secrets
        },
        body: jsonEncode(payload),
      );
      debugPrint("Notif Pengumuman sukses ditembak!");
    } catch (e) {
      debugPrint("Error kirim notif pengumuman: $e");
    }
  }
  // 👆 ------------------------------------------------------------- 👆

  @override
  Widget build(BuildContext context) {
    if (churchId == null) return const Scaffold(body: Center(child: Text("ID Gereja Kosong")));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(widget.filterKategorial ?? "Jadwal Ibadah", style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900], 
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('churches').doc(churchId).collection('jadwal')
            .orderBy('tanggal', descending: false).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.indigo));
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
                    child: Column(
                      children: [
                        Icon(Icons.event_busy, size: 60, color: Colors.grey),
                        SizedBox(height: 10),
                        Text(
                          "Belum ada jadwal ibadah", 
                          style: TextStyle(color: Colors.grey, fontSize: 16)
                        ),
                      ],
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
        elevation: 4,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
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
              borderRadius: BorderRadius.circular(15), 
              border: Border.all(color: Colors.orange.shade300, width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.orange.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))
              ]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.campaign, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text("Pengumuman", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800], fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(teks, style: const TextStyle(fontSize: 14, height: 1.4)),
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
    
    final List<Map<String, dynamic>> rows = [
      {'label': 'W.L', 'val': pelayan['Worship Leader'], 'icon': Icons.mic_external_on},
      {'label': 'Singer', 'val': pelayan['Singer'], 'icon': Icons.queue_music},
      {'label': 'Musik', 'val': pelayan['Pemain Musik'], 'icon': Icons.piano},
      {'label': 'Tamborin', 'val': pelayan['Pemain Tamborin'] ?? pelayan['Tamborin'], 'icon': Icons.celebration}, 
      {'label': 'Operator LCD', 'val': pelayan['Operator LCD'], 'icon': Icons.desktop_mac},
      {'label': 'Kolektan', 'val': pelayan['Kolektan'], 'icon': Icons.volunteer_activism},
      {'label': 'Doa Syafaat', 'val': pelayan['Doa Syafaat'], 'icon': Icons.front_hand},
      {'label': 'Penerima Tamu', 'val': pelayan['Penerima Tamu'], 'icon': Icons.waving_hand},
    ];

    final visibleRows = rows.where((r) => r['val'] != null && r['val'].toString().trim().isNotEmpty).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      child: InkWell(
        onLongPress: isAdmin ? () => _showEditDeleteDialog(doc.id, namaKeg) : null,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.circular(15), 
            border: Border.all(color: Colors.indigo.shade100, width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.indigo.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
            ]
          ),
          child: ExpansionTile(
            title: Text(namaKeg, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.indigo)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.access_time_filled, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(_formatTanggalSultan(data['waktu'] ?? '-'), style: TextStyle(color: Colors.grey[800], fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 14, color: Colors.redAccent),
                      const SizedBox(width: 6),
                      Text(data['tempat'] ?? '-', style: TextStyle(color: Colors.grey[800], fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ),
            children: [
              const Divider(height: 1),

              if (data['deskripsi'] != null && data['deskripsi'].toString().trim().isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16), 
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50.withOpacity(0.5), 
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.menu_book, size: 16, color: Colors.orange.shade800),
                          const SizedBox(width: 8),
                          Text("Firman Tuhan / Tema:", style: TextStyle(color: Colors.orange.shade800, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${data['deskripsi']}", 
                        style: const TextStyle(
                          fontSize: 18, 
                          fontWeight: FontWeight.w900, 
                          color: Colors.black87,
                          height: 1.4 
                        )
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1.5),
              ],

              ...List.generate(visibleRows.length, (index) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: index % 2 == 0 ? Colors.white : Colors.indigo.shade50.withOpacity(0.3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(visibleRows[index]['icon'], size: 20, color: Colors.indigo.shade300),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 100, 
                        child: Text(visibleRows[index]['label'], style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w500))
                      ),
                      Expanded(
                        child: Text(
                          visibleRows[index]['val'].toString().replaceAll(", ", "\n"), 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87) 
                        )
                      ),
                    ],
                  ),
                );
              }),
              
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _navigasiSusunan(doc.id, namaKeg),
                        icon: const Icon(Icons.list_alt),
                        label: const Text("Susunan Acara", style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo, 
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                        ),
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () => _navigasiTambahEdit(doc.id), 
                        icon: const Icon(Icons.edit, color: Colors.orange),
                        label: const Text("Edit", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Colors.orange, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                        ),
                      ),
                    ]
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
            // 👇 UBAH JADI ASYNC AGAR BISA KIRIM NOTIF 👇
            onPressed: () async {
              String teksBaru = controller.text.trim();
              
              // 1. Tutup dialognya dulu biar aplikasinya terasa cepat
              Navigator.pop(context);
              
              // 2. Simpan ke database
              await _db.collection('churches').doc(churchId).collection('pengumuman').doc(docId).set({'teks': teksBaru});
              
              // 3. Panggil kurir notif kalau teksnya tidak kosong
              if (teksBaru.isNotEmpty) {
                await _sendPengumumanNotification(teksBaru);
              }
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pengumuman disimpan & Notif dikirim!"), backgroundColor: Colors.green));
              }
            }, 
            child: const Text("Simpan & Kirim Notif")
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