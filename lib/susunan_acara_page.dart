import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_manager.dart';

class SusunanAcaraPage extends StatefulWidget {
  final String jadwalId;
  final String namaKegiatan;

  const SusunanAcaraPage({super.key, required this.jadwalId, required this.namaKegiatan});

  @override
  State<SusunanAcaraPage> createState() => _SusunanAcaraPageState();
}

class _SusunanAcaraPageState extends State<SusunanAcaraPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final UserManager _userManager = UserManager();

  // --- LOGIKA EDIT (Sesuai EditSusunanAcaraActivity) ---
  void _showEditDialog(String field, List<String> currentData) {
    if (!_userManager.isAdmin()) return;

    // Gabungkan list jadi satu teks dengan baris baru agar mudah diedit
    final controller = TextEditingController(text: currentData.join("\n"));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit ${field == 'urutanAcara' ? 'Urutan Acara' : 'Daftar Lagu'}"),
        content: TextField(
          controller: controller,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: "Gunakan baris baru untuk setiap poin...",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () async {
              String? churchId = _userManager.getChurchIdForCurrentView();
              // Pecah kembali teks menjadi List berdasarkan baris baru
              List<String> newData = controller.text.split("\n").where((s) => s.trim().isNotEmpty).toList();

              await _db.collection("churches").doc(churchId)
                  .collection("jadwal").doc(widget.jadwalId).update({
                field: newData,
              });

              if (mounted) Navigator.pop(context);
            },
            child: const Text("Simpan"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String? churchId = _userManager.getChurchIdForCurrentView();

    return DefaultTabController(
      length: 2, // 2 Tab: Urutan Acara & Daftar Lagu
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.namaKegiatan),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.format_list_numbered), text: "Urutan Acara"),
              Tab(icon: Icon(Icons.music_note), text: "Daftar Lagu"),
            ],
            indicatorColor: Colors.white,
          ),
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: _db.collection("churches").doc(churchId)
              .collection("jadwal").doc(widget.jadwalId).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            
            var data = snapshot.data!.data() as Map<String, dynamic>?;
            
            // Ambil data List (Persis logika Kotlin Bos)
            List<String> urutan = List<String>.from(data?['urutanAcara'] ?? ["Belum diatur."]);
            List<String> lagu = List<String>.from(data?['daftarLagu'] ?? ["Belum diatur."]);

            return TabBarView(
              children: [
                _buildListView(urutan, "urutanAcara"),
                _buildListView(lagu, "daftarLagu"),
              ],
            );
          },
        ),
        floatingActionButton: _userManager.isAdmin() 
          ? Builder( // Builder agar bisa akses TabController
              builder: (context) => FloatingActionButton.extended(
                onPressed: () {
                  final index = DefaultTabController.of(context).index;
                  if (index == 0) {
                    _showEditDialog("urutanAcara", urutan); // Error di sini butuh variabel lokal
                  } else {
                    _showEditDialog("daftarLagu", lagu);
                  }
                },
                label: const Text("Edit Acara"),
                icon: const Icon(Icons.edit),
              ),
            )
          : null,
      ),
    );
  }

  // --- WIDGET LIST VIEW (PENGGANTI FRAGMENT) ---
  Widget _buildListView(List<String> items, String fieldType) {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nomor Urut (Bulatan Indigo)
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(color: Colors.indigo, shape: BoxShape.circle),
                child: Center(
                  child: Text("${index + 1}", 
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 15),
              // Teks Acara
              Expanded(
                child: Text(items[index], 
                  style: const TextStyle(fontSize: 16, height: 1.4)),
              ),
            ],
          ),
        );
      },
    );
  }
}