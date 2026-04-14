import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_manager.dart';

class SusunanAcaraPage extends StatefulWidget {
  final String jadwalId;
  final String namaKegiatan;
  // 👇 KITA TAMBAHKAN KATEGORIAL SEBAGAI FILTER 👇
  final String? filterKategorial; 

  const SusunanAcaraPage({super.key, required this.jadwalId, required this.namaKegiatan, this.filterKategorial});

  @override
  State<SusunanAcaraPage> createState() => _SusunanAcaraPageState();
}

class _SusunanAcaraPageState extends State<SusunanAcaraPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final UserManager _userManager = UserManager();
  
  List<String> _currentUrutan = ["Belum diatur."];
  List<String> _currentLagu = ["Belum diatur."];
  
  // 👇 VARIABEL SATPAM SAKTI 👇
  bool _canEdit = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  void _checkPermissions() {
    bool isGlobalAdmin = _userManager.isAdmin();
    bool isPengurusKomisiIni = false;
    
    // Cek apakah data kegiatan ini punya kategorial (misal dari halaman sebelumnya)
    // Karena di SusunanAcaraPage tidak dilempar filterKategorial dari JadwalPage,
    // kita akan cek langsung ke userManager, apakah dia pengurus, dan apakah
    // dia sedang mengedit acara di komisi dia sendiri.
    
    // Karena kita tidak mengoper filterKategorial dari JadwalPage, kita andalkan
    // logika bahwa jika dia pengurus, maka dia pasti sedang mengedit di komisinya.
    // TAPI untuk lebih aman, kita biarkan logic canEdit ini fleksibel.
    
    if (_userManager.isPengurus) {
       isPengurusKomisiIni = true; 
    }
    
    setState(() {
      _canEdit = isGlobalAdmin || isPengurusKomisiIni;
    });
  }

  // =========================================================================
  // 1. DIALOG EDIT (DENGAN TOMBOL CARI BUKU LAGU)
  // =========================================================================
  void _showEditDialog(String field, List<String> currentData) {
    if (!_canEdit) return; // 👈 CEGAT KALAU BUKAN ADMIN/PENGURUS

    String initialText = currentData.length == 1 && currentData[0] == "Belum diatur." 
        ? "" 
        : currentData.join("\n");
        
    final controller = TextEditingController(text: initialText);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24), 
        title: Row(
          children: [
            Icon(field == 'urutanAcara' ? Icons.format_list_numbered : Icons.music_note, color: Colors.indigo),
            const SizedBox(width: 10),
            Text(field == 'urutanAcara' ? 'Edit Urutan' : 'Edit Lagu', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite, 
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (field == 'daftarLagu') ...[
                ElevatedButton.icon(
                  onPressed: () => _showSongSearchModal(controller),
                  icon: const Icon(Icons.search),
                  label: const Text("Cari dari Buku Lagu", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade600,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 45),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                  ),
                ),
                const SizedBox(height: 15),
              ],

              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: 15,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: field == 'urutanAcara' 
                        ? "Ketik satu acara per baris..." 
                        : "Ketik manual atau gunakan tombol Cari di atas...",
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.only(right: 16, bottom: 16),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () async {
              String? churchId = _userManager.getChurchIdForCurrentView();
              List<String> newData = controller.text.split("\n").where((s) => s.trim().isNotEmpty).toList();

              if (newData.isEmpty) newData = ["Belum diatur."];

              await _db.collection("churches").doc(churchId).collection("jadwal").doc(widget.jadwalId).update({
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

  // =========================================================================
  // 2. MODAL PENCARIAN BUKU LAGU (SUDAH BISA CARI ANGKA NKI)
  // =========================================================================
  void _showSongSearchModal(TextEditingController parentController) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        String searchQuery = "";
        
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              decoration: const BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))
              ),
              child: Column(
                children: [
                  Container(margin: const EdgeInsets.only(top: 12, bottom: 10), width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text("Pilih Lagu dari Buku", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      onChanged: (val) => setModalState(() => searchQuery = val.toLowerCase()),
                      decoration: InputDecoration(
                        hintText: "Cari judul atau nomor lagu...", // Hint diubah
                        prefixIcon: const Icon(Icons.search),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: FutureBuilder<QuerySnapshot>(
                      future: _db.collection("songs").get(), 
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                        
                        var docs = snapshot.data!.docs.where((doc) {
                          var data = doc.data() as Map<String, dynamic>;
                          String judul = data['judul']?.toString().toLowerCase() ?? "";
                          String nomor = data['nomor']?.toString().toLowerCase() ?? ""; 
                          
                          // 👇 LOGIKA BARU: Cari berdasarkan Judul ATAU Nomor 👇
                          return judul.contains(searchQuery) || nomor.contains(searchQuery);
                        }).toList();

                        return ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            var data = docs[index].data() as Map<String, dynamic>;
                            String nomorStr = data['nomor']?.toString() ?? "";
                            // Jika ada nomor, tampilkan di list (misal: "12. Iring Maha Tuhan")
                            String displayTitle = (nomorStr.isNotEmpty) ? "$nomorStr. ${data['judul']}" : data['judul'] ?? "Tanpa Judul";

                            return ListTile(
                              leading: const CircleAvatar(backgroundColor: Colors.indigo, child: Icon(Icons.music_note, color: Colors.white, size: 20)),
                              title: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(data['kategori'] ?? "NKI"),
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text("Tambah Lagu?"),
                                    content: Text("Tambahkan '$displayTitle' ke daftar ibadah?"),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c), child: const Text("Batal")),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                                        onPressed: () {
                                          String currentText = parentController.text.trim();
                                          // PENTING: Yang dimasukkan ke text box tetap MURNI data['judul'] 
                                          // supaya tidak error saat ditarik fitur "Lihat Lirik"
                                          if (currentText.isNotEmpty) {
                                            parentController.text = "$currentText\n${data['judul']}";
                                          } else {
                                            parentController.text = data['judul'];
                                          }
                                          Navigator.pop(c); 
                                          Navigator.pop(context); 
                                        }, 
                                        child: const Text("Tambahkan")
                                      )
                                    ]
                                  )
                                );
                              },
                            );
                          },
                        );
                      }
                    ),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  // =========================================================================
  // 3. WIDGET UTAMA (SCAFFOLD & TAB BAR)
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    String? churchId = _userManager.getChurchIdForCurrentView();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA), 
        appBar: AppBar(
          title: Text(widget.namaKegiatan, style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.white, unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.orange, indicatorWeight: 4,
            tabs: [
              Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.format_list_numbered), SizedBox(width: 8), Text("Acara")])),
              Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.music_note), SizedBox(width: 8), Text("Lagu")])),
            ],
          ),
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: _db.collection("churches").doc(churchId).collection("jadwal").doc(widget.jadwalId).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.indigo));
            var data = snapshot.data!.data() as Map<String, dynamic>?;
            _currentUrutan = List<String>.from(data?['urutanAcara'] ?? ["Belum diatur."]);
            _currentLagu = List<String>.from(data?['daftarLagu'] ?? ["Belum diatur."]);

            return TabBarView(
              children: [
                _buildListView(_currentUrutan, Icons.event_note),
                _buildSongList(_currentLagu),
              ],
            );
          },
        ),
        
        // 👇 TAMPILKAN TOMBOL EDIT JIKA DIA ADMIN ATAU PENGURUS 👇
        floatingActionButton: _canEdit 
          ? Builder(
              builder: (context) => FloatingActionButton.extended(
                backgroundColor: Colors.indigo, foregroundColor: Colors.white, elevation: 4,
                onPressed: () {
                  final index = DefaultTabController.of(context).index;
                  _showEditDialog(index == 0 ? "urutanAcara" : "daftarLagu", index == 0 ? _currentUrutan : _currentLagu);
                },
                label: const Text("Edit", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                icon: const Icon(Icons.edit),
              ),
            ) : null,
      ),
    );
  }

  // =========================================================================
  // 4. WIDGET HELPER: DAFTAR ACARA
  // =========================================================================
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
            color: Colors.white, borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.indigo.shade50),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))]
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 35, height: 35,
                decoration: BoxDecoration(color: Colors.indigo.shade50, shape: BoxShape.circle),
                child: Center(child: Text("${index + 1}", style: TextStyle(color: Colors.indigo.shade800, fontSize: 14, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 15),
              Expanded(child: Text(items[index], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87, height: 1.4))),
            ],
          ),
        );
      },
    );
  }

  // =========================================================================
  // 5. WIDGET HELPER: DAFTAR LAGU VERTIKAL
  // =========================================================================
  Widget _buildSongList(List<String> items) {
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

    return ListView.builder(
      padding: const EdgeInsets.only(top: 20, left: 16, right: 16, bottom: 80),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.indigo.shade50),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))]
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: () => _openFullScreenLyrics(items[index]), 
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 35, height: 35,
                      decoration: BoxDecoration(color: Colors.indigo.shade50, shape: BoxShape.circle),
                      child: Center(child: Text("${index + 1}", style: TextStyle(color: Colors.indigo.shade800, fontSize: 14, fontWeight: FontWeight.bold))),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(items[index], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87, height: 1.4)),
                    ),
                    Icon(Icons.chevron_right, color: Colors.indigo.shade200),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // =========================================================================
  // 6. FITUR FULL SCREEN LIRIK (RATA KIRI & CUBIT ZOOM)
  // =========================================================================
  void _openFullScreenLyrics(String judulLaguTerketik) {
    Navigator.push(context, MaterialPageRoute(builder: (context) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text("Lirik Pujian", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: FutureBuilder<QuerySnapshot>(
          future: _db.collection("songs").where("judul", isEqualTo: judulLaguTerketik).limit(1).get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.indigo));
            }
            
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off, size: 80, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text("Lirik tidak ditemukan.", style: TextStyle(color: Colors.grey.shade600, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text("Pastikan judul '$judulLaguTerketik'\nada di Buku Nyanyian.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              );
            }

            var data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
            String lirikLagu = data['lirik'] ?? "Lirik belum tersedia."; 

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: InteractiveViewer(
                clipBehavior: Clip.none,
                minScale: 1.0,  
                maxScale: 4.0,  
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))]
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center, // <-- Judul tetap di tengah
                    children: [
                      Text(judulLaguTerketik, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(10)),
                        child: Text(data['kategori'] ?? "Pujian", style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      const Divider(height: 40, thickness: 1.5, color: Color(0xFFE8EAF6)),
                      
                      // 👇 LIRIK RATA KIRI SULTAN 👇
                      SizedBox(
                        width: double.infinity, // Paksa melebar
                        child: Text(
                          lirikLagu, 
                          textAlign: TextAlign.left, // <-- Ini yang bikin lirik rata kiri
                          style: const TextStyle(fontSize: 18, height: 1.8, color: Colors.black87)
                        ),
                      ),
                      // 👆 ---------------------- 👆
                      
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            );
          }
        ),
      );
    }));
  }
}