import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_manager.dart';

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

  Future<void> _loadJemaat() async {
    String? churchId = _userManager.getChurchIdForCurrentView();
    if (churchId == null || churchId.isEmpty) return;

    try {
      // Query berdasarkan id gereja aktif
      Query query = _db.collection("churches").doc(churchId).collection("jemaat");
      
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

  // --- FITUR HAPUS JEMAAT ---
  void _hapusJemaat(String id, String nama) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus Data"),
        content: Text("Yakin ingin menghapus data $nama?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              String? churchId = _userManager.getChurchIdForCurrentView();
              await _db.collection("churches").doc(churchId).collection("jemaat").doc(id).delete();
              _loadJemaat(); // Refresh data
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // --- FITUR TAMBAH / EDIT JEMAAT (DIALOg) ---
  void _showFormJemaat({Map<String, dynamic>? data}) {
    final namaController = TextEditingController(text: data?['namaLengkap']);
    final kelompokController = TextEditingController(text: data?['kelompok'] ?? widget.filterKategorial);
    final statusController = TextEditingController(text: data?['status'] ?? "Jemaat");

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(data == null ? "Tambah Jemaat" : "Edit Jemaat", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextField(controller: namaController, decoration: const InputDecoration(labelText: "Nama Lengkap")),
            TextField(controller: kelompokController, decoration: const InputDecoration(labelText: "Kelompok (Kategorial)")),
            TextField(controller: statusController, decoration: const InputDecoration(labelText: "Status")),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                String? churchId = _userManager.getChurchIdForCurrentView();
                final payload = {
                  "namaLengkap": namaController.text,
                  "kelompok": kelompokController.text,
                  "status": statusController.text,
                  "updatedAt": FieldValue.serverTimestamp(),
                };

                if (data == null) {
                  await _db.collection("churches").doc(churchId).collection("jemaat").add(payload);
                } else {
                  await _db.collection("churches").doc(churchId).collection("jemaat").doc(data['id']).update(payload);
                }
                
                if (mounted) Navigator.pop(context);
                _loadJemaat();
              },
              child: Text(data == null ? "Simpan" : "Update"),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Data Jemaat")),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _filteredJemaat.length,
              itemBuilder: (context, index) {
                final j = _filteredJemaat[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(j['namaLengkap']?[0] ?? "?")),
                    title: Text(j['namaLengkap'] ?? ""),
                    subtitle: Text("${j['status']} • ${j['kelompok']}"),
                    
                    // KLIK LAMA UNTUK MENU EDIT/HAPUS (HANYA ADMIN)
                    onLongPress: () {
                      if (_userManager.isAdmin()) {
                        showModalBottomSheet(
                          context: context,
                          builder: (context) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.edit),
                                title: const Text("Edit"),
                                onTap: () {
                                  Navigator.pop(context);
                                  _showFormJemaat(data: j);
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.delete, color: Colors.red),
                                title: const Text("Hapus"),
                                onTap: () {
                                  Navigator.pop(context);
                                  _hapusJemaat(j['id'], j['namaLengkap']);
                                },
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  ),
                );
              },
            ),
            
      // TOMBOL TAMBAH JEMAAT (HANYA ADMIN)
      floatingActionButton: _userManager.isAdmin() 
          ? FloatingActionButton.extended(
              onPressed: () => _showFormJemaat(),
              label: const Text("Jemaat Baru"),
              icon: const Icon(Icons.add),
            )
          : null,
    );
  }
}