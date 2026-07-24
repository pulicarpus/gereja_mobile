import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class AsetGerejaPage extends StatefulWidget {
  final String? churchId; // Opsional: diambil dari UserManager().getChurchIdForCurrentView()

  const AsetGerejaPage({super.key, this.churchId});

  @override
  State<AsetGerejaPage> createState() => _AsetGerejaPageState();
}

class _AsetGerejaPageState extends State<AsetGerejaPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Fungsi untuk Memilih Gambar (Kamera / Galeri)
  Future<XFile?> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80, // Kompres ukuran gambar agar hemat storage
      );
      return pickedFile;
    } catch (e) {
      debugPrint("Error pilih gambar: $e");
      return null;
    }
  }

  // Fungsi Upload Gambar ke Firebase Storage
  Future<String?> _uploadImage(XFile imageFile) async {
    try {
      String fileName = "aset_${DateTime.now().millisecondsSinceEpoch}.jpg";
      Reference ref = _storage.ref().child("aset_gereja_photos").child(fileName);

      UploadTask uploadTask = ref.putFile(File(imageFile.path));
      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint("Error upload foto: $e");
      return null;
    }
  }

  // Fungsi Modal / BottomSheet untuk Pilih Sumber Foto
  void _showImageSourceDialog(Function(XFile?) onImageSelected) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF1A237E)),
                title: const Text("Pilih dari Galeri"),
                onTap: () async {
                  Navigator.pop(context);
                  XFile? img = await _pickImage(ImageSource.gallery);
                  onImageSelected(img);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF1A237E)),
                title: const Text("Ambil Foto Kamera"),
                onTap: () async {
                  Navigator.pop(context);
                  XFile? img = await _pickImage(ImageSource.camera);
                  onImageSelected(img);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // --- FUNGSI MENAMPILKAN DETAIL ASET (BOTTOM SHEET) ---
  void _showDetailAsetDialog(Map<String, dynamic> data) {
    String namaAset = data['namaAset'] ?? 'Aset Tanpa Nama';
    int jumlah = data['jumlah'] ?? 1;
    String status = data['status'] ?? 'Baik';
    String lokasi = data['lokasi'] ?? '-';
    String kategori = data['kategori'] ?? 'Umum';
    String keterangan = data['keterangan'] ?? '';
    String? fotoUrl = data['fotoUrl'];

    Color statusColor = _getStatusColor(status);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Garis Pegangan (Handle Drag)
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 15),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    // Foto Ukuran Besar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        height: 220,
                        color: Colors.grey.shade200,
                        child: (fotoUrl != null && fotoUrl.isNotEmpty)
                            ? Image.network(
                                fotoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 60, color: Colors.grey),
                              )
                            : const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.inventory_2, size: 60, color: Color(0xFF1A237E)),
                                    SizedBox(height: 8),
                                    Text("Tidak ada foto aset", style: TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Header Nama & Status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            namaAset,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    const Divider(height: 1),
                    const SizedBox(height: 15),

                    // Daftar Rincian Detail
                    _buildDetailRow(Icons.category, "Kategori", kategori),
                    _buildDetailRow(Icons.numbers, "Jumlah / Unit", "$jumlah Unit"),
                    _buildDetailRow(Icons.location_on, "Lokasi Simpan / Ruangan", lokasi),
                    _buildDetailRow(
                      Icons.notes,
                      "Keterangan Tambahan",
                      keterangan.isNotEmpty ? keterangan : "Tidak ada keterangan.",
                    ),

                    const SizedBox(height: 25),

                    // Tombol Tutup
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A237E),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Tutup", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Widget Pembantu untuk Baris Detail
  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF1A237E)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Fungsi Tambah / Edit Aset
  void _showAsetDialog({DocumentSnapshot? doc}) {
    final bool isEdit = doc != null;
    final Map<String, dynamic>? data = isEdit ? doc.data() as Map<String, dynamic>? : null;

    final namaController = TextEditingController(text: data?['namaAset'] ?? '');
    final jumlahController = TextEditingController(text: data?['jumlah']?.toString() ?? '1');
    final lokasiController = TextEditingController(text: data?['lokasi'] ?? '');
    final keteranganController = TextEditingController(text: data?['keterangan'] ?? '');
    final customKategoriController = TextEditingController();

    String status = data?['status'] ?? 'Baik';
    String kategoriDB = data?['kategori'] ?? 'Elektronik';
    String? existingFotoUrl = data?['fotoUrl'];

    XFile? selectedNewImage;
    bool isLoading = false;

    final List<String> statusList = ['Baik', 'Rusak Ringan', 'Rusak Berat'];
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

    String kategoriTerpilih = kategoriList.contains(kategoriDB) ? kategoriDB : 'Lainnya (Buat Sendiri)';
    if (kategoriTerpilih == 'Lainnya (Buat Sendiri)' && data != null && !kategoriList.contains(kategoriDB)) {
      customKategoriController.text = kategoriDB;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
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
                    // --- AREA PILIH FOTO ASET ---
                    GestureDetector(
                      onTap: () {
                        _showImageSourceDialog((XFile? img) {
                          if (img != null) {
                            setDialogState(() {
                              selectedNewImage = img;
                            });
                          }
                        });
                      },
                      child: Container(
                        height: 140,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
                        ),
                        child: selectedNewImage != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(selectedNewImage!.path),
                                  fit: BoxFit.cover,
                                ),
                              )
                            : (existingFotoUrl != null && existingFotoUrl.isNotEmpty)
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(
                                      existingFotoUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 50),
                                    ),
                                  )
                                : const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_a_photo, size: 40, color: Color(0xFF1A237E)),
                                      SizedBox(height: 5),
                                      Text(
                                        "Ketuk untuk tambah foto aset",
                                        style: TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                      ),
                    ),
                    const SizedBox(height: 15),

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
                if (!isLoading)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Batal", style: TextStyle(color: Colors.grey)),
                  ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (namaController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Nama aset tidak boleh kosong!")),
                            );
                            return;
                          }

                          setDialogState(() => isLoading = true);

                          String? finalFotoUrl = existingFotoUrl;

                          // Jika pengguna memilih foto baru, upload ke Firebase Storage
                          if (selectedNewImage != null) {
                            String? uploadedUrl = await _uploadImage(selectedNewImage!);
                            if (uploadedUrl != null) {
                              finalFotoUrl = uploadedUrl;
                            }
                          }

                          String kategoriFinal = kategoriTerpilih;
                          if (kategoriTerpilih == 'Lainnya (Buat Sendiri)' &&
                              customKategoriController.text.trim().isNotEmpty) {
                            kategoriFinal = customKategoriController.text.trim();
                          }

                          final payload = {
                            'namaAset': namaController.text.trim(),
                            'jumlah': int.tryParse(jumlahController.text.trim()) ?? 1,
                            'kategori': kategoriFinal,
                            'status': status,
                            'lokasi': lokasiController.text.trim(),
                            'keterangan': keteranganController.text.trim(),
                            'fotoUrl': finalFotoUrl ?? '',
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
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(isEdit ? "Simpan" : "Tambah", style: const TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Fungsi Konfirmasi Hapus Data
  void _confirmDelete(String docId, String? fotoUrl) {
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

              // Hapus data dari Firestore
              await ref.doc(docId).delete();

              // Opsional: Hapus file foto dari Firebase Storage jika ada
              if (fotoUrl != null && fotoUrl.isNotEmpty) {
                try {
                  await _storage.refFromURL(fotoUrl).delete();
                } catch (e) {
                  debugPrint("Error hapus file foto: $e");
                }
              }

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
                    String? fotoUrl = data['fotoUrl'];

                    Color statusColor = _getStatusColor(status);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      child: InkWell( // 👉 Penambahan fitur klik untuk melihat rincian BottomSheet
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _showDetailAsetDialog(data),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Gambar Thumbnail Aset
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 70,
                                  height: 70,
                                  color: Colors.grey.shade200,
                                  child: (fotoUrl != null && fotoUrl.isNotEmpty)
                                      ? Image.network(
                                          fotoUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
                                        )
                                      : const Icon(Icons.inventory_2, color: Color(0xFF1A237E), size: 35),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Detail Aset
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            namaAset,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            status,
                                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.category, size: 13, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text("$kategori ($jumlah Unit)", style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(Icons.location_on, size: 13, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            lokasi,
                                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (keterangan.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        "Ket: $keterangan",
                                        style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        InkWell(
                                          onTap: () => _showAsetDialog(doc: doc),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            child: Row(
                                              children: [
                                                Icon(Icons.edit, size: 14, color: Colors.blue),
                                                SizedBox(width: 3),
                                                Text("Edit", style: TextStyle(color: Colors.blue, fontSize: 11)),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        InkWell(
                                          onTap: () => _confirmDelete(doc.id, fotoUrl),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete, size: 14, color: Colors.red),
                                                SizedBox(width: 3),
                                                Text("Hapus", style: TextStyle(color: Colors.red, fontSize: 11)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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

      // Floating Action Button
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