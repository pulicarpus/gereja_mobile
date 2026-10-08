import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_manager.dart';
import 'app_safety.dart';
import 'add_edit_jemaat_page.dart';
import 'dashboard_page.dart'; 
import 'detail_jemaat_page.dart'; 
import 'daftar_keluarga_page.dart';
import 'loading_sultan.dart';
import 'kategorial_config.dart';

class DataJemaatPage extends StatefulWidget {
  final String? filterKategorial;
  const DataJemaatPage({super.key, this.filterKategorial});

  @override
  State<DataJemaatPage> createState() => _DataJemaatPageState();
}

class _DataJemaatPageState extends State<DataJemaatPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final UserManager _userManager = UserManager();
  
  List<Map<String, dynamic>> _allJemaat = [];
  List<Map<String, dynamic>> _filteredJemaat = [];
  bool _isLoading = true;
  int _loadGeneration = 0;
  bool _isSearching = false;
  String? _loadError;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadJemaat();
  }

  Future<void> _loadJemaat() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final uid = _userManager.userId;
    String? churchId = _userManager.getChurchIdForCurrentView();
    if (churchId == null) {
      if (mounted) setState(() { _isLoading = false; _loadError = "Data gereja tidak valid."; });
      return;
    }
    if (mounted) setState(() { _isLoading = true; _loadError = null; });
    try {
      final snapshot = await _db
          .collection("churches")
          .doc(churchId)
          .collection("jemaat")
          .get().timeout(const Duration(seconds: 20));
      var tempData = snapshot.docs.map((doc) {
        final source = doc.data() as Map<String, dynamic>;
        return <String, dynamic>{...source, 'id': doc.id};
      }).toList();

      final kategori = widget.filterKategorial?.trim();
      if (kategori != null && kategori.isNotEmpty) {
        tempData = tempData
            .where((j) => KategorialConfig.same(j['kelompok'], kategori))
            .toList();
      }

      // Urutkan berdasarkan nama secara default
      tempData.sort((a, b) => (a['namaLengkap'] ?? "").toString().toLowerCase().compareTo((b['namaLengkap'] ?? "").toString().toLowerCase()));

      // Saring data aktif (kecuali yang berstatus 'Meninggal') untuk tampilan list
      var activeData = tempData.where((j) => j['status'] != 'Meninggal').toList();

      if (mounted && generation == _loadGeneration && _userManager.userId == uid && _userManager.getChurchIdForCurrentView() == churchId) {
        setState(() {
          _allJemaat = tempData;        // SEMUA data (termasuk meninggal) untuk Dashboard
          _filteredJemaat = activeData; // Hanya data aktif untuk ListView
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && generation == _loadGeneration) setState(() { _loadError = "Gagal memuat data jemaat."; });
    } finally {
      if (mounted && generation == _loadGeneration) setState(() {
        _isLoading = false;
        if (_userManager.userId != uid || _userManager.getChurchIdForCurrentView() != churchId) {
          _allJemaat = []; _filteredJemaat = [];
          _loadError = "Sesi atau gereja aktif berubah. Buka ulang halaman.";
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _initial(Map<String, dynamic> j) {
    return nameInitial(j['namaLengkap']);
  }

  // --- LOGIKA PENCARIAN ---
  void _filterSearch(String query) {
    setState(() {
      _filteredJemaat = _allJemaat
          .where((j) => 
            j['status'] != 'Meninggal' && 
            [
              j['namaLengkap'], j['nomorTelepon'], j['alamat'], j['kelompok']
            ].any((v) => (v ?? '').toString().toLowerCase().contains(query.toLowerCase()))
          )
          .toList();
    });
  }

  void _goToDashboard() {
    Navigator.push(
      context, 
      MaterialPageRoute(
        builder: (context) => DashboardPage(
          allJemaat: _allJemaat,
          churchId: _userManager.getChurchIdForCurrentView(), // <-- Pastikan dikirim ke sini
        ),
      ),
    ).then((_) {
      // Refresh data jemaat saat kembali dari dashboard jika ada yang dibatalkan/dihapus
      _loadJemaat();
    });
  }

  // --- DETAIL JEMAAT (BOTTOM SHEET) ---
  bool _performingAction = false;
  Future<void> _performJemaatAction(Map<String, dynamic> book, {required bool remove, required String? church}) async {
    if (_performingAction || !mounted) return;
    if (church == null) return;
    _performingAction = true;
    try {
      final id = book['id']?.toString() ?? '';
      if (id.isEmpty) throw StateError('ID jemaat tidak valid.');
      if (remove) {
        await deleteUnlinkedJemaat(church, id);
      } else {
        await changeJemaatStatus(church, id, 'Meninggal');
      }
      if (mounted) await _loadJemaat();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Aksi belum berhasil: $e')));
    } finally {
      _performingAction = false;
    }
  }

  void _showDetailJemaat(Map<String, dynamic> j) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => DetailJemaatPage(jemaatData: j),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching 
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(hintText: "Cari nama jemaat...", border: InputBorder.none),
              onChanged: _filterSearch,
            )
          : Text(widget.filterKategorial ?? "Data Jemaat"),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _filteredJemaat = _allJemaat.where((j) => j['status'] != 'Meninggal').toList();
                }
              });
            },
          ),
          if (widget.filterKategorial == null ||
              widget.filterKategorial!.trim().isEmpty)
            IconButton(
              tooltip: "Daftar Keluarga",
              icon: const Icon(Icons.family_restroom),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DaftarKeluargaPage(),
                  ),
                );
              },
            ),
          IconButton(
            tooltip: "Dashboard Statistik",
            onPressed: _goToDashboard, 
            icon: const Icon(Icons.dashboard_customize_rounded)
          ),
        ],
      ),
      body: _isLoading
        ? LoadingSultan(size: 80)
        : _loadError != null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(_loadError!),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _loadJemaat, child: const Text("COBA LAGI")),
            ]))
          : _filteredJemaat.isEmpty
            ? RefreshIndicator(
                onRefresh: _loadJemaat,
                child: ListView(children: const [
                  SizedBox(height: 180),
                  Icon(Icons.people_outline, size: 56, color: Colors.grey),
                  SizedBox(height: 12),
                  Center(child: Text("Tidak ada data jemaat yang cocok.", style: TextStyle(color: Colors.grey))),
                ]),
              )
            : RefreshIndicator(
            onRefresh: _loadJemaat,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80, top: 10),
              itemCount: _filteredJemaat.length,
              itemBuilder: (context, index) {
                final j = _filteredJemaat[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 2,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    leading: Hero(
                      tag: 'foto_list_${j['id']}',
                      child: CircleAvatar(
                        radius: 25,
                        backgroundImage: (j['fotoProfil'] != null && j['fotoProfil'] != "") ? NetworkImage(j['fotoProfil']) : null,
                        child: (j['fotoProfil'] == null || j['fotoProfil'] == "") ? Text(_initial(j)) : null,
                      ),
                    ),
                    title: Text(j['namaLengkap'] ?? "-", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("${j['statusKeluarga']} • ${j['kelompok']}"),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                    onTap: () => _showDetailJemaat(j),
                    onLongPress: () { if (_userManager.isAdmin()) _showAksiAdmin(j); },
                  ),
                );
              },
            ),
          ),
      floatingActionButton: _userManager.isAdmin() 
        ? FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddEditJemaatPage(
                  initialKelompok: widget.filterKategorial,
                ),
              ),
            ).then((v) => _loadJemaat()),
            label: const Text("Tambah Jemaat"), 
            icon: const Icon(Icons.person_add_alt_1_rounded),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
          ) : null,
    );
  }

  Future<bool> _confirmAksi(String title, String message, {bool danger = false}) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Batal")),
          ElevatedButton(
            style: danger ? ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Lanjutkan"),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showAksiAdmin(Map<String, dynamic> j) {
    final church = _userManager.getChurchIdForCurrentView();
    showModalBottomSheet(
      context: context, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min, 
        children: [
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.edit_note_rounded), 
            title: const Text("Edit Data Jemaat"), 
            onTap: () { 
              Navigator.pop(context); 
              Navigator.push(context, MaterialPageRoute(builder: (c) => AddEditJemaatPage(jemaatData: j))).then((v) => _loadJemaat()); 
            },
          ),
          ListTile(
            leading: const Icon(Icons.heart_broken_rounded, color: Colors.orange), 
            title: const Text("Tandai Meninggal"), 
            onTap: () async { 
              Navigator.pop(context);
              final ok = await _confirmAksi("Tandai Meninggal", "Yakin menandai ${j['namaLengkap'] ?? 'jemaat ini'} sebagai meninggal?");
              if (!ok) return;
              await _performJemaatAction(j, remove: false, church: church); 
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_rounded, color: Colors.red), 
            title: const Text("Hapus Permanen", style: TextStyle(color: Colors.red)), 
            onTap: () async {
              Navigator.pop(context);
              final ok = await _confirmAksi("Hapus Permanen", "Data ${j['namaLengkap'] ?? 'jemaat ini'} akan dihapus permanen. Tindakan ini tidak dapat dibatalkan.", danger: true);
              if (!ok) return;
              await _performJemaatAction(j, remove: true, church: church); 
            },
          ),
          const SizedBox(height: 20),
        ]
      )
    );
  }
}

