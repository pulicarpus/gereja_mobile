import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_manager.dart';
// Note: Kita akan buat halaman Detail dan AddEdit ini nanti
// import 'detail_lagu_page.dart';
// import 'add_edit_lagu_page.dart'; 

class LaguPage extends StatefulWidget {
  const LaguPage({super.key});

  @override
  State<LaguPage> createState() => _LaguPageState();
}

class _LaguPageState extends State<LaguPage> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  
  bool _isAdmin = false;
  List<Map<String, dynamic>> _fullSongList = [];
  List<Map<String, dynamic>> _filteredList = [];
  bool _isLoading = true;
  String _currentCategory = "NKI";

  @override
  void initState() {
    super.initState();
    _isAdmin = UserManager().isAdmin();
    _tabController = TabController(length: 2, vsync: this);
    
    // Dengarkan perubahan Tab
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        _currentCategory = _tabController.index == 0 ? "NKI" : "KONTEMPORER";
        _applyFilterAndSearch();
      });
    });

    _loadSongsFromFirestore();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // --- AMBIL DATA DARI FIREBASE ---
  Future<void> _loadSongsFromFirestore() async {
    setState(() => _isLoading = true);

    try {
      // Mengambil koleksi lagu secara global (bukan per gereja, agar semua gereja bisa pakai db lagu yang sama)
      final snapshot = await _db.collection("songs").get();
      
      List<Map<String, dynamic>> tempList = [];
      WriteBatch batch = _db.batch();
      bool hasUpdates = false;

      for (var doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data();
        data['id'] = doc.id; // Simpan ID dokumen
        
        // Pengecekan Kategori Default "NKI" seperti di Kotlin
        if (!data.containsKey('kategori') || data['kategori'] == null) {
          batch.update(doc.reference, {'kategori': 'NKI'});
          data['kategori'] = 'NKI';
          hasUpdates = true;
        }
        tempList.add(data);
      }

      if (hasUpdates) await batch.commit();

      // --- ALGORITMA SORTING ANGKA CERDAS (1, 2, 10) ---
      tempList.sort((a, b) {
        String numA = a['nomor']?.toString() ?? "";
        String numB = b['nomor']?.toString() ?? "";
        
        int extractNum(String s) {
          final RegExp regExp = RegExp(r'\d+');
          final match = regExp.firstMatch(s);
          return match != null ? int.parse(match.group(0)!) : 0;
        }

        int c = extractNum(numA).compareTo(extractNum(numB));
        if (c != 0) return c;
        return numA.compareTo(numB);
      });

      setState(() {
        _fullSongList = tempList;
        _isLoading = false;
        _applyFilterAndSearch();
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal memuat daftar lagu")));
    }
  }

  // --- LOGIKA FILTER KATEGORI & PENCARIAN ---
  void _applyFilterAndSearch() {
    String query = _searchController.text.toLowerCase();
    
    setState(() {
      _filteredList = _fullSongList.where((song) {
        String kategori = song['kategori']?.toString() ?? "NKI";
        bool matchCategory = kategori.toUpperCase() == _currentCategory;
        
        bool matchSearch = query.isEmpty || 
            (song['judul']?.toString().toLowerCase().contains(query) ?? false) ||
            (song['nomor']?.toString().toLowerCase().contains(query) ?? false) ||
            (song['lirik']?.toString().toLowerCase().contains(query) ?? false); // Tambahan: bisa cari dari lirik
            
        return matchCategory && matchSearch;
      }).toList();
    });
  }

  // --- DIALOG AKSI ADMIN ---
  void _showEditDeleteDialog(Map<String, dynamic> song) {
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
            child: Text("Kelola: ${song['judul']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo), textAlign: TextAlign.center,),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.orange), 
            title: const Text("Edit Lagu"), 
            onTap: () { 
              Navigator.pop(context); 
              // TODO: Navigasi ke AddEditLaguPage
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fitur Edit menyusul bos!")));
            }
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red), 
            title: const Text("Hapus Lagu", style: TextStyle(color: Colors.red)), 
            onTap: () {
               Navigator.pop(context);
               showDialog(
                 context: context,
                 builder: (c) => AlertDialog(
                   title: const Text("Hapus Lagu?"),
                   content: Text("Lagu '${song['judul']}' akan dihapus permanen untuk semua jemaat."),
                   actions: [
                     TextButton(onPressed: () => Navigator.pop(c), child: const Text("Batal")),
                     ElevatedButton(
                       style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                       onPressed: () async {
                         Navigator.pop(c);
                         await _db.collection('songs').doc(song['id']).delete();
                         _loadSongsFromFirestore(); // Reload data
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Background keabuan lembut
      appBar: AppBar(
        title: const Text("Buku Nyanyian"),
        backgroundColor: Colors.indigo[900], 
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorColor: Colors.orange,
          indicatorWeight: 4,
          tabs: const [
            Tab(text: "NKI / HYMNE"),
            Tab(text: "KONTEMPORER"),
          ],
        ),
      ),
      body: Column(
        children: [
          // ==== SEARCH BAR ====
          Container(
            color: Colors.indigo[900],
            padding: const EdgeInsets.fromLTRB(16, 5, 16, 15),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => _applyFilterAndSearch(), // Auto search saat ngetik
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                hintText: "Cari judul, nomor, atau potongan lirik...",
                hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                suffixIcon: _searchController.text.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        _applyFilterAndSearch();
                        FocusScope.of(context).unfocus();
                      },
                    )
                  : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),
          // ====================

          // ==== DAFTAR LAGU ====
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _filteredList.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.music_off, size: 60, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text("Lagu tidak ditemukan.", style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _filteredList.length,
                      itemBuilder: (context, index) {
                        final song = _filteredList[index];
                        String nomorStr = song['nomor'] != null && song['nomor'].toString().isNotEmpty 
                            ? "${song['nomor']}. " 
                            : "";

                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onLongPress: _isAdmin ? () => _showEditDeleteDialog(song) : null,
                            onTap: () {
                              // TODO: Navigasi ke Detail Lagu
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Detail lagu menyusul bos!")));
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 45,
                                    height: 45,
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.shade50,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.music_note, color: Colors.indigo),
                                  ),
                                  const SizedBox(width: 15),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "$nomorStr${song['judul']}", 
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                                        ),
                                        if (song['pencipta'] != null && song['pencipta'].toString().isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              song['pencipta'], 
                                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: Colors.grey),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
      
      // ==== TOMBOL TAMBAH KHUSUS ADMIN ====
      floatingActionButton: _isAdmin 
        ? FloatingActionButton(
            onPressed: () {
              // TODO: Navigasi ke Add Lagu
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Form Tambah Lagu beserta Fitur Scraper kita buat setelah ini!")));
            },
            backgroundColor: Colors.indigo,
            child: const Icon(Icons.add, color: Colors.white),
          ) 
        : null,
    );
  }
}