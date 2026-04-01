import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_manager.dart';
import 'add_edit_jadwal_page.dart'; 
import 'susunan_acara_page.dart';
import 'package:intl/intl.dart';

class JadwalPage extends StatefulWidget {
  final String? filterKategorial; // null = Umum, Isi = Kategorial
  const JadwalPage({super.key, this.filterKategorial});

  @override
  State<JadwalPage> createState() => _JadwalPageState();
}

class _JadwalPageState extends State<JadwalPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final UserManager _userManager = UserManager();
  
  String _pengumumanTeks = "Memuat pengumuman...";
  bool _isLoadingPengumuman = true;

  @override
  void initState() {
    super.initState();
    _loadPengumuman();
  }

  // --- 1. LOGIKA PENGUMUMAN ---
  Future<void> _loadPengumuman() async {
    String? churchId = _userManager.getChurchIdForCurrentView();
    if (churchId == null) return;

    String docId = widget.filterKategorial == null 
        ? "utama" 
        : "pengumuman_${widget.filterKategorial}";

    try {
      var doc = await _db.collection("churches").doc(churchId)
          .collection("pengumuman").doc(docId).get();

      if (mounted) {
        setState(() {
          if (doc.exists) {
            _pengumumanTeks = doc.data()?['teks'] ?? "Tidak ada pengumuman.";
          } else {
            String label = widget.filterKategorial ?? "Gereja";
            _pengumumanTeks = "Belum ada pengumuman $label. Tekan lama untuk membuat.";
          }
          _isLoadingPengumuman = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPengumuman = false);
    }
  }

  void _showEditPengumumanDialog() {
    if (!_userManager.isAdmin()) return;
    
    final controller = TextEditingController(
      text: _pengumumanTeks.contains("Belum ada pengumuman") ? "" : _pengumumanTeks
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Update Pengumuman ${widget.filterKategorial ?? ''}"),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: "Tulis pengumuman baru...",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () => _savePengumuman(controller.text.trim()),
            child: const Text("Simpan & Kirim Notif"),
          ),
        ],
      ),
    );
  }

  Future<void> _savePengumuman(String teks) async {
    if (teks.isEmpty) return;
    String? churchId = _userManager.getChurchIdForCurrentView();
    String docId = widget.filterKategorial == null ? "utama" : "pengumuman_${widget.filterKategorial}";

    await _db.collection("churches").doc(churchId).collection("pengumuman").doc(docId).set({
      "teks": teks,
      "waktuUpdate": Timestamp.now(),
      "kategori": widget.filterKategorial
    });

    if (mounted) Navigator.pop(context);
    _loadPengumuman();
  }

  // --- 2. HELPER UI UNTUK PETUGAS (Sudah diganti ke WL) ---
  Widget _buildPetugasRow(IconData icon, String label, String? nama) {
    if (nama == null || nama.isEmpty || nama == "-") return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.indigo),
          const SizedBox(width: 10),
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Expanded(child: Text(nama, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String? churchId = _userManager.getChurchIdForCurrentView();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.filterKategorial == null 
            ? "Jadwal Ibadah" 
            : "Kegiatan ${widget.filterKategorial}"),
      ),
      body: Column(
        children: [
          // --- HEADER PENGUMUMAN ---
          GestureDetector(
            onLongPress: _showEditPengumumanDialog,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(15),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.amber.shade200, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.campaign_rounded, color: Colors.orange),
                      const SizedBox(width: 10),
                      Text("PENGUMUMAN", 
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_pengumumanTeks, style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
          ),

          // --- LIST JADWAL ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection("churches").doc(churchId).collection("jadwal")
                  .orderBy("tanggal", descending: false).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("Belum ada jadwal kegiatan."));
                }

                var filteredDocs = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  String? kat = data['kategoriKegiatan'];
                  if (widget.filterKategorial == null) {
                    return kat == null || kat == "Umum" || kat == "";
                  } else {
                    return kat == widget.filterKategorial;
                  }
                }).toList();

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    var doc = filteredDocs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      child: ExpansionTile(
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.event_note, color: Colors.indigo),
                        ),
                        title: Text(data['namaKegiatan'] ?? "-", 
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("📅 ${data['waktu'] ?? '-'}"),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(15.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("PETUGAS PELAYANAN:", 
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                const SizedBox(height: 5),
                                // --- DI SINI SUDAH JADI WL BOS ---
                                _buildPetugasRow(Icons.person, "WL", data['w1']), 
                                _buildPetugasRow(Icons.mic, "Singer", data['singer']),
                                _buildPetugasRow(Icons.music_note, "Musik", data['musik']),
                                _buildPetugasRow(Icons.auto_awesome, "Tamborin", data['tamborin']),
                                const Divider(),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.push(context, MaterialPageRoute(
                                          builder: (c) => SusunanAcaraPage(
                                            jadwalId: doc.id,
                                            namaKegiatan: data['namaKegiatan'] ?? "Kegiatan",
                                          )
                                        ));
                                      },
                                      icon: const Icon(Icons.menu_book),
                                      label: const Text("Liturgi"),
                                    ),
                                    if (_userManager.isAdmin())
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.orange),
                                        onPressed: () {
                                          Navigator.push(context, MaterialPageRoute(
                                            builder: (c) => AddEditJadwalPage(
                                              jadwalId: doc.id,
                                              filterKategorial: widget.filterKategorial,
                                            )
                                          ));
                                        },
                                      ),
                                  ],
                                )
                              ],
                            ),
                          )
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _userManager.isAdmin() 
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (c) => AddEditJadwalPage(filterKategorial: widget.filterKategorial)
                ));
              },
              label: const Text("Tambah"),
              icon: const Icon(Icons.add),
            ) 
          : null,
    );
  }
}