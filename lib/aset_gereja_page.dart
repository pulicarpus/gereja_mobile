import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AsetGerejaPage extends StatefulWidget {
  final String? churchId; // Opsional: pasang churchId jika sistem multi-gereja

  const AsetGerejaPage({super.key, this.churchId});

  @override
  State<AsetGerejaPage> createState() => _AsetGerejaPageState();
}

class _AsetGerejaPageState extends State<AsetGerejaPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Fungsi untuk Menambah / Mengedit Aset
  void _showAsetDialog({DocumentSnapshot? doc}) {
    final bool isEdit = doc != null;
    final Map<String, dynamic>? data = isEdit ? doc.data() as Map<String, dynamic>? : null;

    final namaController = TextEditingController(text: data?['namaAset'] ?? '');
    final jumlahController = TextEditingController(text: data?['jumlah']?.toString() ?? '1');
    final lokasiController = TextEditingController(text: data?['lokasi'] ?? '');
    final keteranganController = TextEditingController(text: data?['keterangan'] ?? '');
    final customKategoriController = TextEditingController(); // Controller untuk kategori buat sendiri

    String status = data?['status'] ?? 'Baik';
    String kategoriDB = data?['kategori'] ?? 'Elektronik';

    final List<String> statusList = ['Baik', 'Rusak Ringan', 'Rusak Berat'];
    
    // Daftar kategori yang sudah ditambahkan Tanah, Kebun, Bangunan
    final List<String> kategoriList = [
      'Elektronik', 
      'Mebel', 
      'Musik', 
      'Kendaraan', 
      'Tanah', 
      'Kebun', 
      'Bangunan', 
      'Lainnya (Buat Sendiri)'
    ];

    // Logika jika saat edit, kategorinya adalah kategori kustom (misal "Pena" atau "Bahan")
    String kategoriTerpilih = kategoriList.contains(kategoriDB) ? kategoriDB : 'Lainnya (Buat Sendiri)';
    if (kategoriTerpilih == 'Lainnya (Buat Sendiri)' && data != null && !kategoriList.contains(kategoriDB)) {
      customKategoriController.text = kategoriDB;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: Text(
                isEdit ? "Edit Aset" : "Tambah Aset Baru",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: namaController,
                      decoration: const InputDecoration(
                        labelText: "Nama Aset / Barang",
                        prefixIcon: Icon(Icons.inventory),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: jumlahController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "Jumlah",
                              prefixIcon: Icon(Icons.numbers),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: kategoriTerpilih,
                            decoration: const InputDecoration(labelText: "Kategori"),
                            items: kategoriList.map((String item) {
                              return DropdownMenuItem(value: item, child: Text(item, style: const TextStyle(fontSize: 12)));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setDialogState(() => kategoriTerpilih = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    
                    // MUNCULKAN INPUT TEXT JIKA MEMILIH "Lainnya (Buat Sendiri)"
                    if (kategoriTerpilih == 'Lainnya (Buat Sendiri)') ...[
                      TextField(
                        controller: customKategoriController,
                        decoration: const InputDecoration(
                          labelText: "Tulis Kategori Baru",
                          hintText: "Misal: Pena, Bahan, Alat Tulis...",
                          prefixIcon: Icon(Icons.edit_note),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    DropdownButtonFormField<String>(
                      value: statusList.contains(status) ? status : statusList.first,
                      decoration: const InputDecoration(labelText: "Kondisi / Status"),
                      items: statusList.map((String item) {
                        return DropdownMenuItem(value: item, child: Text(item));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => status = val);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: lokasiController,
                      decoration: const InputDecoration(
                        labelText: "Lokasi / Ruangan",
                        prefixIcon: Icon(Icons.location_on),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: keteranganController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: "Keterangan (Opsional)",
                        prefixIcon: Icon(Icons.notes),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Batal", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    if (namaController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Nama aset tidak boleh kosong!")),
                      );
                      return;
                    }

                    // Menentukan kategori akhir yang disimpan ke database
                    String kategoriFinal = kategoriTerpilih;
                    if (kategoriTerpilih == 'Lainnya (Buat Sendiri)' && customKategoriController.text.trim().isNotEmpty) {
                      kategoriFinal = customKategoriController.text.trim();
                    }

                    final payload = {
                      'namaAset': namaController.text.trim(),
                      'jumlah': int.tryParse(jumlahController.text.trim()) ?? 1,
                      'kategori': kategoriFinal,
                      'status': status,
                      'lokasi': lokasiController.text.trim(),
                      'keterangan': keteranganController.text.trim(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    };

                    CollectionReference ref;
                    if (widget.churchId != null && widget.churchId!.isNotEmpty) {
                      ref = _db.collection('churches').doc(widget.churchId).collection('aset');
                    } else {
                      ref = _db.collection('aset_gereja');
                    }

                    if (isEdit) {
                      await ref.doc(doc.id).update(payload);
                    } else {
                      payload['createdAt'] = FieldValue.serverTimestamp();
                      await ref.add(payload);
                    }

                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isEdit ? "Aset diperbarui!" : "Aset berhasil ditambahkan!"),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  child: Text(isEdit ? "Simpan" : "Tambah", style: const TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Fungsi Konfirmasi Hapus Data
  void _confirmDelete(String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus Aset"),
        content: const Text("Apakah Anda yakin ingin menghapus aset ini dari inventaris?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          TextButton(
            onPressed: () async {
              CollectionReference ref;
              if (widget.churchId != null && widget.churchId!.isNotEmpty) {
                ref = _db.collection('churches').doc(widget.churchId).collection('aset');
              } else {
                ref = _db.collection('aset_gereja');
              }

              await ref.doc(docId).delete();
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Aset berhasil dihapus")),
                );
              }
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Baik':
        return Colors.green;
      case 'Rusak Ringan':
        return Colors.orange;
      case 'Rusak Berat':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    Query query;
    if (widget.churchId != null && widget.churchId!.isNotEmpty) {
      query = _db.collection('churches').doc(widget.churchId).collection('aset');
    } else {
      query = _db.collection('aset_gereja');
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("Aset & Inventaris Gereja"),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Bar Pencarian
          Container(
            padding: const EdgeInsets.all(15),
            color: const Color(0xFF1A237E),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.toLowerCase().trim();
                });
              },
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                hintText: "Cari nama barang atau lokasi...",
                hintStyle: const TextStyle(color: Colors.grey),
                fillColor: Colors.white,
                filled: true,
                prefixIcon: const Icon(Icons.search, color: Color(0xFF1A237E)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = "";
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // List Data Aset
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: query.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey),
                        SizedBox(height: 10),
                        Text("Belum ada data aset gereja.", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                var docs = snapshot.data!.docs;

                // Filtering lokasi/nama secara manual
                if (_searchQuery.isNotEmpty) {
                  docs = docs.where((doc) {
                    var data = doc.data() as Map<String, dynamic>;
                    String nama = (data['namaAset'] ?? '').toString().toLowerCase();
                    String lokasi = (data['lokasi'] ?? '').toString().toLowerCase();
                    String kategori = (data['kategori'] ?? '').toString().toLowerCase();
                    return nama.contains(_searchQuery) ||
                        lokasi.contains(_searchQuery) ||
                        kategori.contains(_searchQuery);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return const Center(
                    child: Text("Aset yang dicari tidak ditemukan.", style: TextStyle(color: Colors.grey)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var doc = docs[index];
                    var data = doc.data() as Map<String, dynamic>;

                    String namaAset = data['namaAset'] ?? 'Aset Tanpa Nama';
                    int jumlah = data['jumlah'] ?? 1;
                    String status = data['status'] ?? 'Baik';
                    String lokasi = data['lokasi'] ?? '-';
                    String kategori = data['kategori'] ?? 'Umum';
                    String keterangan = data['keterangan'] ?? '';

                    Color statusColor = _getStatusColor(status);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    namaAset,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.category, size: 14, color: Colors.grey),
                                const SizedBox(width: 5),
                                Text("$kategori ($jumlah Unit)", style: const TextStyle(fontSize: 13, color: Colors.black87)),
                                const SizedBox(width: 15),
                                const Icon(Icons.location_on, size: 14, color: Colors.grey),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    lokasi,
                                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (keterangan.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                "Ket: $keterangan",
                                style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                              ),
                            ],
                            const Divider(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                InkWell(
                                  onTap: () => _showAsetDialog(doc: doc),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 16, color: Colors.blue),
                                        SizedBox(width: 4),
                                        Text("Edit", style: TextStyle(color: Colors.blue, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 15),
                                InkWell(
                                  onTap: () => _confirmDelete(doc.id),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, size: 16, color: Colors.red),
                                        SizedBox(width: 4),
                                        Text("Hapus", style: TextStyle(color: Colors.red, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),

      // Floating Action Button untuk Tambah Aset
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text("Tambah Aset"),
        onPressed: () => _showAsetDialog(),
      ),
    );
  }
}