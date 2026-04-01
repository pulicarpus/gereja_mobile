import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_manager.dart';
import 'package:intl/intl.dart'; // Untuk format tanggal

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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPengumuman();
  }

  // --- BAGIAN PENGUMUMAN ---
  Future<void> _loadPengumuman() async {
    String? churchId = _userManager.getChurchIdForCurrentView();
    if (churchId == null) return;

    // ID Dokumen: 'utama' atau 'pengumuman_Sekolah Minggu'
    String docId = widget.filterKategorial == null 
        ? "utama" 
        : "pengumuman_${widget.filterKategorial}";

    try {
      var doc = await _db.collection("churches").doc(churchId)
          .collection("pengumuman").doc(docId).get();

      setState(() {
        if (doc.exists) {
          _pengumumanTeks = doc.data()?['teks'] ?? "Tidak ada pengumuman.";
        } else {
          _pengumumanTeks = "Belum ada pengumuman ${widget.filterKategorial ?? 'Gereja'}.";
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _pengumumanTeks = "Gagal memuat pengumuman.");
    }
  }

  void _showEditPengumuman() {
    if (!_userManager.isAdmin()) return;
    
    TextEditingController controller = TextEditingController(
      text: _pengumumanTeks.contains("Belum ada") ? "" : _pengumumanTeks
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Update Pengumuman ${widget.filterKategorial ?? ''}"),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(hintText: "Tulis pengumuman di sini..."),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          TextButton(
            onPressed: () => _savePengumuman(controller.text),
            child: const Text("Simpan & Kirim Notif"),
          ),
        ],
      ),
    );
  }

  Future<void> _savePengumuman(String teks) async {
    String? churchId = _userManager.getChurchIdForCurrentView();
    String docId = widget.filterKategorial == null ? "utama" : "pengumuman_${widget.filterKategorial}";

    await _db.collection("churches").doc(churchId)
        .collection("pengumuman").doc(docId).set({
      "teks": teks,
      "waktuUpdate": Timestamp.now(),
      "kategori": widget.filterKategorial
    });

    // Pemicu Notifikasi (Sesuai logika Kotlin lama Bos)
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
          // --- KARTU PENGUMUMAN ---
          GestureDetector(
            onLongPress: _showEditPengumuman,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(15),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.campaign, color: Colors.orange),
                      SizedBox(width: 10),
                      Text("PENGUMUMAN", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(_pengumumanTeks, style: const TextStyle(fontSize: 15)),
                  if (_userManager.isAdmin())
                    const Text("\n*Tekan lama untuk mengedit", style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey)),
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
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                // Filter Manual Seperti di Kotlin Bos
                var docs = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  String? kat = data['kategoriKegiatan'];
                  if (widget.filterKategorial == null) {
                    return kat == null || kat == "Umum" || kat == "";
                  } else {
                    return kat == widget.filterKategorial;
                  }
                }).toList();

                if (docs.isEmpty) return const Center(child: Text("Belum ada jadwal."));

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: ListTile(
                        leading: const CircleAvatar(backgroundColor: Colors.indigo, child: Icon(Icons.event, color: Colors.white)),
                        title: Text(data['namaKegiatan'] ?? "-", style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${data['tanggal']} • ${data['jam']}"),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          // Navigasi ke Susunan Acara nanti di sini
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
          ? FloatingActionButton(
              onPressed: () { /* Navigasi Tambah Jadwal */ },
              child: const Icon(Icons.add),
            ) 
          : null,
    );
  }
}