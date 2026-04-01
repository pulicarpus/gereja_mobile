import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_manager.dart';
import 'add_edit_jadwal_page.dart'; // Pastikan file ini sudah dibuat
import 'package:intl/intl.dart';

class JadwalPage extends StatefulWidget {
  final String? filterKategorial; // null = Umum, Isi = Kategorial (Sekolah Minggu, dll)
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

  // --- LOGIKA PENGUMUMAN (PERSIS KOTLIN BOS) ---
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
          TextButton(
            onPressed: () => _savePengumuman(controller.text.trim()),
            child: const Text("Simpan & Kirim Notif", style: TextStyle(fontWeight: FontWeight.bold)),
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

    // Pemicu Notifikasi Global (Logika Pending Notifications Bos)
    String prefix = widget.filterKategorial != null ? "[${widget.filterKategorial}] " : "";
    await _db.collection("pending_notifications").add({
      "title": "PENGUMUMAN GEREJA",
      "body": prefix + teks,
      "type": "broadcast",
      "churchId": churchId,
      "timestamp": DateTime.now().millisecondsSinceEpoch
    });

    Navigator.pop(context);
    _loadPengumuman();
  }

  // --- LOGIKA HAPUS JADWAL ---
  void _confirmDelete(String id, String nama) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus Jadwal"),
        content: Text("Hapus kegiatan '$nama'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          TextButton(
            onPressed: () async {
              String? churchId = _userManager.getChurchIdForCurrentView();
              await _db.collection("churches").doc(churchId).collection("jadwal").doc(id).delete();
              Navigator.pop(context);
            }, 
            child: const Text("Hapus", style: TextStyle(color: Colors.red))
          ),
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
          // --- CARD PENGUMUMAN ---
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
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.campaign_rounded, color: Colors.orange, size: 28),
                      const SizedBox(width: 10),
                      Text("PENGUMUMAN ${widget.filterKategorial?.toUpperCase() ?? 'UMUM'}", 
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(_pengumumanTeks, style: const TextStyle(fontSize: 15, height: 1.4)),
                  if (_userManager.isAdmin())
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text("*Tahan lama untuk edit pengumuman", 
                        style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey)),
                    ),
                ],
              ),
            ),
          ),

          // --- DAFTAR JADWAL (STREAM BUILDER) ---
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

                // Filter Manual (Sesuai Logika Kotlin Bos)
                var filteredDocs = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  String? kat = data['kategoriKegiatan'];
                  if (widget.filterKategorial == null) {
                    return kat == null || kat == "Umum" || kat == "";
                  } else {
                    return kat == widget.filterKategorial;
                  }
                }).toList();

                if (filteredDocs.isEmpty) return const Center(child: Text("Tidak ada jadwal untuk kategori ini."));

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    var doc = filteredDocs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 3,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(15),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.event_available, color: Colors.indigo),
                        ),
                        title: Text(data['namaKegiatan'] ?? "-", 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("📅 ${data['waktu'] ?? '-'}"),
                              if (data['tempat'] != null && data['tempat'] != "")
                                Text("📍 ${data['tempat']}"),
                            ],
                          ),
                        ),
                        trailing: _userManager.isAdmin() 
                          ? IconButton(
                              icon: const Icon(Icons.edit_note, color: Colors.grey),
                              onPressed: () {
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (c) => AddEditJadwalPage(
                                    jadwalId: doc.id,
                                    filterKategorial: widget.filterKategorial,
                                  )
                                ));
                              },
                            )
                          : const Icon(Icons.chevron_right),
                        onTap: () {
                          // TODO: Navigasi ke Susunan Acara / Liturgi
                        },
                        onLongPress: () {
                          if (_userManager.isAdmin()) _confirmDelete(doc.id, data['namaKegiatan'] ?? "");
                        },
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
              label: const Text("Jadwal Baru"),
              icon: const Icon(Icons.add),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ) 
          : null,
    );
  }
}