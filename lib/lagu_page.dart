import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_manager.dart';
import 'detail_lagu_page.dart';
import 'add_edit_lagu_page.dart';

class LaguPage extends StatefulWidget {
  const LaguPage({super.key});

  @override
  State<LaguPage> createState() => _LaguPageState();
}

class _LaguPageState extends State<LaguPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _fullSongList = [];
  List<Map<String, dynamic>> _filteredList = [];
  bool _isLoading = true;
  String? _loadError;
  String _currentCategory = "NKI";
  int _loadGeneration = 0;

  bool get _canManageSongs => UserManager().isAdmin();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging || !mounted) return;
      setState(() {
        _currentCategory =
            _tabController.index == 0 ? "NKI" : "KONTEMPORER";
      });
      _applyFilterAndSearch();
    });
    _loadSongsFromFirestore();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _categoryGroup(dynamic raw) {
    final value = raw?.toString().trim().toUpperCase() ?? "";
    if (value == "KONTEMPORER") return "KONTEMPORER";
    // Data lama kosong/HYMNE tetap dibaca sebagai kelompok buku NKI tanpa
    // menulis ulang dokumen Firestore.
    return "NKI";
  }

  String _text(dynamic raw, [String fallback = ""]) {
    final value = raw?.toString().trim();
    return (value == null || value.isEmpty) ? fallback : value;
  }

  int? _extractNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  int _compareSongs(Map<String, dynamic> a, Map<String, dynamic> b) {
    final groupA = _categoryGroup(a['kategori']);
    final groupB = _categoryGroup(b['kategori']);

    if (groupA != groupB) return groupA.compareTo(groupB);

    final titleA = _text(a['judul'], "Tanpa Judul").toLowerCase();
    final titleB = _text(b['judul'], "Tanpa Judul").toLowerCase();

    if (groupA == "KONTEMPORER") {
      return titleA.compareTo(titleB);
    }

    final nomorA = _text(a['nomor']);
    final nomorB = _text(b['nomor']);
    final numA = _extractNumber(nomorA);
    final numB = _extractNumber(nomorB);

    if (numA != null && numB != null) {
      final compareNum = numA.compareTo(numB);
      if (compareNum != 0) return compareNum;
      final compareRaw = nomorA.compareTo(nomorB);
      if (compareRaw != 0) return compareRaw;
      return titleA.compareTo(titleB);
    }
    if (numA != null) return -1;
    if (numB != null) return 1;
    return titleA.compareTo(titleB);
  }

  Future<void> _loadSongsFromFirestore() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final snapshot = await _db.collection("songs").get();

      final tempList = snapshot.docs.map((doc) {
        final data = <String, dynamic>{...doc.data()};
        data['id'] = doc.id;
        return data;
      }).toList()
        ..sort(_compareSongs);

      if (!mounted || generation != _loadGeneration) return;

      _fullSongList = tempList;
      _isLoading = false;
      _loadError = null;
      _applyFilterAndSearch();
    } catch (e) {
      debugPrint("Gagal memuat lagu: $e");
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _isLoading = false;
          _loadError = "Daftar lagu gagal dimuat.";
          _fullSongList = [];
          _filteredList = [];
        });
      }
    }
  }

  void _applyFilterAndSearch() {
    if (!mounted) return;

    final query = _searchController.text.trim().toLowerCase();
    final filtered = _fullSongList.where((song) {
      final matchCategory =
          _categoryGroup(song['kategori']) == _currentCategory;
      if (!matchCategory) return false;
      if (query.isEmpty) return true;

      final judul = _text(song['judul']).toLowerCase();
      final nomor = _text(song['nomor']).toLowerCase();
      final lirik = _text(song['lirik']).toLowerCase();
      final pencipta = _text(song['pencipta']).toLowerCase();

      return judul.contains(query) ||
          nomor.contains(query) ||
          lirik.contains(query) ||
          pencipta.contains(query);
    }).toList();

    setState(() => _filteredList = filtered);
  }

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  void _showAdminDialog(Map<String, dynamic> song) {
    if (!_canManageSongs) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _text(song['judul'], "Tanpa Judul"),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.indigo,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.orange),
              title: const Text("Edit Lagu"),
              onTap: () {
                Navigator.pop(sheetContext);
                final id = _text(song['id']);
                if (id.isEmpty) {
                  _showSnack("ID lagu tidak valid.", color: Colors.red);
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddEditLaguPage(
                      songId: id,
                      defaultCategory: _currentCategory,
                    ),
                  ),
                ).then((_) => _loadSongsFromFirestore());
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                "Hapus Lagu",
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete(song);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> song) async {
    if (!_canManageSongs) {
      _showSnack("Anda tidak memiliki izin untuk menghapus lagu.",
          color: Colors.red);
      return;
    }

    final id = _text(song['id']);
    final title = _text(song['judul'], "Tanpa Judul");
    if (id.isEmpty) {
      _showSnack("ID lagu tidak valid.", color: Colors.red);
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text("Hapus Lagu?"),
            content:
                Text("Lagu '$title' akan dihapus permanen dari database."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Batal"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Hapus"),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      await _db.collection('songs').doc(id).delete();
      _showSnack("Lagu berhasil dihapus.");
      await _loadSongsFromFirestore();
    } catch (e) {
      debugPrint("Gagal menghapus lagu: $e");
      _showSnack("Gagal menghapus lagu.", color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          "Buku Nyanyian",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
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
          Container(
            color: Colors.indigo[900],
            padding: const EdgeInsets.fromLTRB(16, 5, 16, 20),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _applyFilterAndSearch(),
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                hintText: "Cari judul, nomor, pencipta, atau lirik...",
                hintStyle: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 14,
                ),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.cloud_off,
                                size: 52,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _loadError!,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: _loadSongsFromFirestore,
                                child: const Text("COBA LAGI"),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _filteredList.isEmpty
                        ? Center(
                            child: Text(
                              "Lagu tidak ditemukan.",
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadSongsFromFirestore,
                            child: ListView.builder(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(12),
                              itemCount: _filteredList.length,
                              itemBuilder: (context, index) {
                                final song = _filteredList[index];
                                final nomor = _text(song['nomor']);
                                final judul =
                                    _text(song['judul'], "Tanpa Judul");
                                final pencipta = _text(
                                  song['pencipta'],
                                  "Pelayan Tuhan",
                                );
                                final displayTitle = nomor.isNotEmpty
                                    ? "$nomor. $judul"
                                    : judul;

                                return Card(
                                  elevation: 1,
                                  margin:
                                      const EdgeInsets.only(bottom: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                  child: ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          Colors.indigo.shade50,
                                      child: const Icon(
                                        Icons.music_note,
                                        color: Colors.indigo,
                                      ),
                                    ),
                                    title: Text(
                                      displayTitle,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    subtitle: Text(
                                      pencipta,
                                      style:
                                          const TextStyle(fontSize: 12),
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right,
                                      color: Colors.grey,
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              DetailLaguPage(
                                            songList:
                                                List<Map<String, dynamic>>.from(
                                              _filteredList,
                                            ),
                                            initialIndex: index,
                                          ),
                                        ),
                                      );
                                    },
                                    onLongPress: _canManageSongs
                                        ? () => _showAdminDialog(song)
                                        : null,
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: _canManageSongs
          ? FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddEditLaguPage(
                      defaultCategory: _currentCategory,
                    ),
                  ),
                ).then((_) => _loadSongsFromFirestore());
              },
              backgroundColor: Colors.indigo,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
}
