import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'user_manager.dart';
import 'add_edit_jemaat_page.dart'; // Pastikan file ini sudah dibuat

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

  @override
  void initState() {
    super.initState();
    _loadJemaat();
  }

  // 1. LOAD DATA DARI FIRESTORE
  Future<void> _loadJemaat() async {
    String? churchId = _userManager.getChurchIdForCurrentView();
    if (churchId == null || churchId.isEmpty) return;

    try {
      Query query = _db.collection("churches").doc(churchId).collection("jemaat");
      
      // Filter jika dibuka dari menu kategorial (Sekolah Minggu, dll)
      if (widget.filterKategorial != null) {
        query = query.where("kelompok", isEqualTo: widget.filterKategorial);
      }

      final snapshot = await query.get();
      final List<Map<String, dynamic>> tempData = snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _allJemaat = tempData;
          _filteredJemaat = tempData;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 2. FITUR INFO LENGKAP (TAMPIL SAAT KLIK)
  void _showDetailJemaat(Map<String, dynamic> j) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 60,
                  backgroundImage: j['fotoProfil'] != null ? NetworkImage(j['fotoProfil']) : null,
                  child: j['fotoProfil'] == null ? Text(j['namaLengkap']?[0] ?? "?", style: const TextStyle(fontSize: 40)) : null,
                ),
              ),
              const SizedBox(height: 15),
              Center(child: Text(j['namaLengkap'] ?? "-", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
              Center(child: Text("${j['statusKeluarga']} • ${j['kelompok']}", style: const TextStyle(color: Colors.grey))),
              const Divider(height: 40),
              
              _buildInfoTile(Icons.phone, "Telepon", j['nomorTelepon'] ?? "-"),
              _buildInfoTile(Icons.wc, "Jenis Kelamin", j['jenisKelamin'] ?? "-"),
              _buildInfoTile(Icons.cake, "Tgl Lahir", j['tanggalLahir'] ?? "-"),
              _buildInfoTile(Icons.location_on, "Alamat", j['alamat'] ?? "-"),
              _buildInfoTile(Icons.favorite, "Status Nikah", j['statusPernikahan'] ?? "-"),
              _buildInfoTile(Icons.water_drop, "Baptis", j['statusBaptis'] ?? "-"),
              _buildInfoTile(Icons.star, "Karunia", j['karuniaPelayanan'] ?? "-"),
              
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showKeluarga(j['idKepalaKeluarga'], j['namaLengkap']),
                      icon: const Icon(Icons.family_restroom),
                      label: const Text("Lihat Keluarga"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (j['nomorTelepon'] != null && j['nomorTelepon'] != "-")
                    IconButton.filled(
                      onPressed: () => launchUrl(Uri.parse("tel:${j['nomorTelepon']}")),
                      icon: const Icon(Icons.call),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 3. FITUR KELUARGA (Sesuai Logika ID Kepala Keluarga Bos)
  void _showKeluarga(String? idKK, String? nama) {
    if (idKK == null || idKK.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data keluarga belum diatur")));
      return;
    }
    final keluarga = _allJemaat.where((j) => j['idKepalaKeluarga'] == idKK).toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Keluarga $nama"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: keluarga.length,
            itemBuilder: (context, i) => ListTile(
              leading: const Icon(Icons.person),
              title: Text(keluarga[i]['namaLengkap'] ?? ""),
              subtitle: Text(keluarga[i]['statusKeluarga'] ?? ""),
            ),
          ),
        ),
        actions: [
          // Tombol Tambah Anggota Keluarga Baru
          if (_userManager.isAdmin())
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (c) => AddEditJemaatPage(idKepalaKeluargaBaru: idKK))).then((v) => _loadJemaat());
              },
              child: const Text("Tambah Anggota"),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tutup")),
        ],
      ),
    );
  }

  // 4. FITUR STATISTIK
  void _showStatistik() {
    Map<String, int> stats = {};
    for (var j in _allJemaat) {
      String k = j['kelompok'] ?? "Lainnya";
      stats[k] = (stats[k] ?? 0) + 1;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Statistik Jemaat"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text("Total Jemaat"), trailing: Text("${_allJemaat.length}")),
            const Divider(),
            ...stats.entries.map((e) => ListTile(title: Text(e.key), trailing: Text("${e.value}"))),
          ],
        ),
      ),
    );
  }

  // 5. AKSI ADMIN (EDIT / HAPUS)
  void _showAksiAdmin(Map<String, dynamic> j) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text("Edit Data"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (c) => AddEditJemaatPage(jemaatData: j))).then((v) => _loadJemaat());
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text("Hapus Jemaat"),
            onTap: () => _konfirmasiHapus(j),
          ),
        ],
      ),
    );
  }

  void _konfirmasiHapus(Map<String, dynamic> j) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus?"),
        content: Text("Yakin ingin menghapus ${j['namaLengkap']}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Tutup Dialog
              Navigator.pop(context); // Tutup BottomSheet
              String? cid = _userManager.getChurchIdForCurrentView();
              await _db.collection("churches").doc(cid).collection("jemaat").doc(j['id']).delete();
              _loadJemaat();
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: Colors.indigo),
      title: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(label),
      dense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.filterKategorial ?? "Data Jemaat"),
        actions: [IconButton(onPressed: _showStatistik, icon: const Icon(Icons.bar_chart))],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            itemCount: _filteredJemaat.length,
            itemBuilder: (context, index) {
              final j = _filteredJemaat[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: j['fotoProfil'] != null ? NetworkImage(j['fotoProfil']) : null,
                    child: j['fotoProfil'] == null ? Text(j['namaLengkap']?[0] ?? "?") : null,
                  ),
                  title: Text(j['namaLengkap'] ?? "-", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${j['statusKeluarga']} • ${j['kelompok']}"),
                  onTap: () => _showDetailJemaat(j),
                  onLongPress: () {
                    if (_userManager.isAdmin()) _showAksiAdmin(j);
                  },
                ),
              );
            },
          ),
      floatingActionButton: _userManager.isAdmin() 
        ? FloatingActionButton.extended(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (c) => const AddEditJemaatPage())).then((v) => _loadJemaat());
            },
            label: const Text("Tambah"),
            icon: const Icon(Icons.person_add),
          )
        : null,
    );
  }
}