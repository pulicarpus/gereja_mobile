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
  
  // Simpan data di sini agar bisa diakses oleh FAB
  List<String> _currentUrutan = ["Belum diatur."];
  List<String> _currentLagu = ["Belum diatur."];

  void _showEditDialog(String field, List<String> currentData) {
    if (!_userManager.isAdmin()) return;

    // Bersihkan teks "Belum diatur." jika mau diedit pertama kali
    String initialText = currentData.length == 1 && currentData[0] == "Belum diatur." 
        ? "" 
        : currentData.join("\n");
        
    final controller = TextEditingController(text: initialText);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        // Trik biar Dialognya nggak terlalu nempel ke pinggir layar tapi tetap lebar maksimal
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24), 
        title: Row(
          children: [
            Icon(
              field == 'urutanAcara' ? Icons.format_list_numbered : Icons.music_note, 
              color: Colors.indigo
            ),
            const SizedBox(width: 10),
            Text(
              field == 'urutanAcara' ? 'Edit Urutan' : 'Edit Lagu', 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)
            ),
          ],
        ),
        // BUNGKUS DENGAN SIZEDBOX AGAR MELEBAR MAKSIMAL KE SAMPING
        content: SizedBox(
          width: double.maxFinite, 
          child: TextField(
            controller: controller,
            maxLines: 15, // Baris diperbanyak jadi 15 biar makin lega ke bawah
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: field == 'urutanAcara' 
                  ? "Ketik satu acara per baris...\nContoh:\nDoa Pembukaan\nPuji-pujian\nFirman Tuhan" 
                  : "Ketik satu lagu per baris...\nContoh:\nKJ 1 - Haleluya\nPKJ 2...",
              hintStyle: TextStyle(color: Colors.grey.shade400),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15), 
                borderSide: const BorderSide(color: Colors.indigo, width: 2)
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.only(right: 16, bottom: 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text("Batal", style: TextStyle(color: Colors.grey))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo, 
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () async {
              String? churchId = _userManager.getChurchIdForCurrentView();
              List<String> newData = controller.text.split("\n").where((s) => s.trim().isNotEmpty).toList();

              // Jika kosong setelah diedit, kembalikan ke default
              if (newData.isEmpty) {
                newData = ["Belum diatur."];
              }

              await _db.collection("churches").doc(churchId)
                  .collection("jadwal").doc(widget.jadwalId).update({
                field: newData,
              });

              if (mounted) Navigator.pop(context);
            },
            child: const Text("Simpan", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String? churchId = _userManager.getChurchIdForCurrentView();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA), // Latar abu-abu agar card menonjol
        appBar: AppBar(
          title: Text(widget.namaKegiatan, style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.orange, // Garis bawah warna orange
            indicatorWeight: 4,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Icon(Icons.format_list_numbered), SizedBox(width: 8), Text("Acara")],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Icon(Icons.music_note), SizedBox(width: 8), Text("Lagu")],
                ),
              ),
            ],
          ),
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: _db.collection("churches").doc(churchId)
              .collection("jadwal").doc(widget.jadwalId).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.indigo));
            
            var data = snapshot.data!.data() as Map<String, dynamic>?;
            
            _currentUrutan = List<String>.from(data?['urutanAcara'] ?? ["Belum diatur."]);
            _currentLagu = List<String>.from(data?['daftarLagu'] ?? ["Belum diatur."]);

            return TabBarView(
              children: [
                _buildListView(_currentUrutan, Icons.event_note), // Tab 1: Susunan Acara (Vertikal)
                _buildSongCarousel(_currentLagu),                 // Tab 2: Lagu (Horizontal Swipe)
              ],
            );
          },
        ),
        floatingActionButton: _userManager.isAdmin() 
          ? Builder(
              builder: (context) => FloatingActionButton.extended(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                elevation: 4,
                onPressed: () {
                  final index = DefaultTabController.of(context).index;
                  if (index == 0) {
                    _showEditDialog("urutanAcara", _currentUrutan);
                  } else {
                    _showEditDialog("daftarLagu", _currentLagu);
                  }
                },
                label: const Text("Edit", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                icon: const Icon(Icons.edit),
              ),
            )
          : null,
      ),
    );
  }

  // 👇 WIDGET HELPER 1: DAFTAR ACARA VERTIKAL 👇
  Widget _buildListView(List<String> items, IconData emptyIcon) {
    if (items.length == 1 && items[0] == "Belum diatur.") {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(emptyIcon, size: 80, color: Colors.indigo.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text("Belum Ada Data", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Text("Admin belum menambahkan daftar ini.", style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 20, left: 16, right: 16, bottom: 80),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.indigo.shade50),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 35, height: 35,
                decoration: BoxDecoration(color: Colors.indigo.shade50, shape: BoxShape.circle),
                child: Center(
                  child: Text("${index + 1}", style: TextStyle(color: Colors.indigo.shade800, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  items[index], 
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87, height: 1.4)
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 👇 WIDGET HELPER 2: CAROUSEL LAGU HORIZONTAL (PENGGANTI VIEWPAGER) 👇
  Widget _buildSongCarousel(List<String> items) {
    if (items.length == 1 && items[0] == "Belum diatur.") {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.queue_music, size: 80, color: Colors.indigo.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text("Belum Ada Lagu", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            const Text("Admin belum mengatur daftar pujian.", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 20),
        // Petunjuk visual untuk jemaat
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.swipe_left, size: 16, color: Colors.grey.shade500),
            const SizedBox(width: 8),
            Text("Geser untuk melihat lagu berikutnya", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            Icon(Icons.swipe_right, size: 16, color: Colors.grey.shade500),
          ],
        ),
        const SizedBox(height: 10),
        
        Expanded(
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.85), // 0.85 agar ujung kartu selanjutnya kelihatan
            itemCount: items.length,
            itemBuilder: (context, index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.indigo, Color(0xFF1A237E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(color: Colors.indigo.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))
                  ]
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.music_note, size: 80, color: Colors.white.withOpacity(0.2)),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "Lagu Ke-${index + 1} dari ${items.length}", 
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)
                      ),
                    ),
                    const SizedBox(height: 25),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        items[index],
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, height: 1.4)
                      ),
                    ),
                  ],
                ),
              );
            }
          ),
        ),
        const SizedBox(height: 80), // Jarak aman untuk tombol Edit di bawah
      ],
    );
  }
}