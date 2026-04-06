import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ==== IMPORT SEMUA HALAMAN TERKAIT ====
import 'user_manager.dart';
import 'detail_lagu_page.dart';    // Halaman baca lirik
import 'add_edit_lagu_page.dart';  // Halaman asisten Gemini

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
    
    // Dengarkan perubahan Tab (NKI atau KONTEMPORER)
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
      final snapshot = await _db.collection("songs").get();
      
      List<Map<String, dynamic>> tempList = [];
      WriteBatch batch = _db.batch();
      bool hasUpdates = false;

      for (var doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data();
        data['id'] = doc.id; 
        
        // Standarisasi kategori jika ada data kosong
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal memuat daftar lagu")));
      }
    }
  }

  // --- LOGIKA FILTER KATEGORI & PENCARIAN REAL-TIME ---
  void _applyFilterAndSearch() {
    String query = _searchController.text.toLowerCase();
    
    setState(() {
      _filteredList = _fullSongList.where((song) {
        String kategori = song['kategori']?.toString() ?? "NKI";
        bool matchCategory = kategori.toUpperCase() == _currentCategory;
        
        // Pencarian maut: Cek Judul, Nomor, atau bahkan potongan Lirik!
        bool matchSearch = query.isEmpty || 
            (song['judul']?.toString().toLowerCase().contains(query) ?? false) ||
            (song['nomor']?.toString().toLowerCase().contains(query) ?? false) ||
            (song['lirik']?.toString().toLowerCase().contains(query) ?? false); 
            
        return matchCategory && matchSearch;
      }).toList();
    });
  }

  // --- MENU RAHASIA ADMIN (DI TEKAN LAMA / LONG PRESS) ---
  void _showAdminDialog(Map<String, dynamic> song) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(song['judul'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo), textAlign: TextAlign.center),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.orange), 
            title: const Text("Edit Lagu"), 
            onTap: () { 
              Navigator.pop(context); 
              Navigator.push(context, MaterialPageRoute(builder: (context) => AddEditLaguPage(
                songId: song['id'], 
                defaultCategory: _currentCategory
              ))).then((_) => _loadSongsFromFirestore()); // Refresh data saat kembali
            }
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red), 
            title: const Text("Hapus Lagu", style: TextStyle(color: Colors.red)), 
            onTap: () {
               Navigator.pop(context);
               _confirmDelete(song);
            }
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> song) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Hapus Lagu?"),
        content: Text("Lagu '${song['judul']}' akan dihapus permanen dari database."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(c);
              await _db.collection('songs').doc(song['id']).delete();
              _loadSongsFromFirestore(); 
            }, 
            child: const Text("Hapus", style: TextStyle(color: Colors.white))
          )
        ]
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), 
      appBar: AppBar(
        title: const Text("Buku Nyanyian", style: TextStyle(fontWeight: FontWeight.bold)),
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
          // ==== SEARCH BAR MODERN ====
          Container(
            color: Colors.indigo[900],
            padding: const EdgeInsets.fromLTRB(16, 5, 16, 20),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => _applyFilterAndSearch(), 
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                hintText: "Cari judul, nomor, atau lirik...",
                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                suffixIcon: _searchController.text.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        _applyFilterAndSearch();
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

          // ==== DAFTAR LAGU ====
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _filteredList.isEmpty
                  ? Center(child: Text("Lagu tidak ditemukan.", style: TextStyle(color: Colors.grey.shade600)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _filteredList.length,
                      itemBuilder: (context, index) {
                        final song = _filteredList[index];
                        String nomor = song['nomor'] ?? "";
                        String displayTitle = (nomor.isNotEmpty) ? "$nomor. ${song['judul']}" : song['judul'];

                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: CircleAvatar(
                              backgroundColor: Colors.indigo.shade50,
                              child: const Icon(Icons.music_note, color: Colors.indigo),
                            ),
                            title: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            subtitle: Text(song['pencipta'] ?? "Pelayan Tuhan", style: const TextStyle(fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                            
                            // MASUK KE DETAIL LIRIK (JEMAAT)
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => DetailLaguPage(songData: song)));
                            },
                            
                            // MENU EDIT/HAPUS (ADMIN)
                            onLongPress: _isAdmin ? () => _showAdminDialog(song) : null,
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
      
      // ==== TOMBOL TAMBAH LAGU + GEMINI (KHUSUS ADMIN) ====
      floatingActionButton: _isAdmin 
        ? FloatingActionButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => AddEditLaguPage(
                defaultCategory: _currentCategory 
              ))).then((_) => _loadSongsFromFirestore()); 
            },
            backgroundColor: Colors.indigo,
            child: const Icon(Icons.add, color: Colors.white),
          ) 
        : null,
    );
  }
}