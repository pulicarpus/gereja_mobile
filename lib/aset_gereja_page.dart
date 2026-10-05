import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'user_manager.dart'; // 👈 PASTIKAN PATH IMPORT INI SESUAI DENGAN LOKASI FILE user_manager.dart ANDA

class AsetGerejaPage extends StatefulWidget {
  final String gerejaId;
  final String namaGereja;

  const AsetGerejaPage({
    Key? key,
    required this.gerejaId,
    required this.namaGereja,
  }) : super(key: key);

  @override
  State<AsetGerejaPage> createState() => _AsetGerejaPageState();
}

class _AsetGerejaPageState extends State<AsetGerejaPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'Semua';

  bool get _canManage {
    final user = UserManager();
    final currentChurchId = user.getChurchIdForCurrentView();
    return user.isAdmin() &&
        currentChurchId != null &&
        currentChurchId.isNotEmpty &&
        currentChurchId == widget.gerejaId;
  }

  String _safeStatus(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    const allowed = {'Baik', 'Rusak Ringan', 'Rusak Berat'};
    return allowed.contains(value) ? value : 'Baik';
  }

  DateTime _sortDate(Map<String, dynamic> data) {
    final raw = data['createdAt'];
    return raw is Timestamp ? raw.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showAsetDialog({DocumentSnapshot? doc}) async {
    if (!_canManage) {
      _showSnack("Anda tidak memiliki izin untuk mengubah aset ini.", color: Colors.red);
      return;
    }

    final formKey = GlobalKey<FormState>();
    final existing = doc?.data() is Map<String, dynamic>
        ? Map<String, dynamic>.from(doc!.data() as Map<String, dynamic>)
        : <String, dynamic>{};

    final namaController = TextEditingController(text: (existing['nama_aset'] ?? '').toString());
    final kategoriController = TextEditingController(text: (existing['kategori'] ?? '').toString());
    final jumlahController = TextEditingController(text: existing['jumlah']?.toString() ?? '');
    final lokasiController = TextEditingController(text: (existing['lokasi'] ?? '').toString());
    final keteranganController = TextEditingController(text: (existing['keterangan'] ?? '').toString());

    String status = _safeStatus(existing['status']);
    final oldFotoUrl = existing['foto_url']?.toString() ?? '';
    String fotoUrl = oldFotoUrl;
    File? imageFile;
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            Future<void> save() async {
              if (saving || !(formKey.currentState?.validate() ?? false)) return;

              final jumlah = int.tryParse(jumlahController.text.trim());
              if (jumlah == null || jumlah <= 0) {
                _showSnack("Jumlah unit harus lebih dari 0.", color: Colors.orange);
                return;
              }

              setStateDialog(() => saving = true);
              Reference? uploadedRef;
              try {
                if (imageFile != null) {
                  uploadedRef = FirebaseStorage.instance
                      .ref()
                      .child('aset_gereja')
                      .child('${widget.gerejaId}_${DateTime.now().millisecondsSinceEpoch}.jpg');
                  await uploadedRef.putFile(imageFile!);
                  fotoUrl = await uploadedRef.getDownloadURL();
                }

                final data = <String, dynamic>{
                  'gerejaId': widget.gerejaId,
                  'nama_aset': namaController.text.trim(),
                  'kategori': kategoriController.text.trim(),
                  'jumlah': jumlah,
                  'lokasi': lokasiController.text.trim(),
                  'status': status,
                  'keterangan': keteranganController.text.trim(),
                  'foto_url': fotoUrl,
                  if (doc == null) 'createdAt': FieldValue.serverTimestamp(),
                };

                if (doc == null) {
                  await _firestore.collection('aset_gereja').add(data);
                } else {
                  await _firestore.collection('aset_gereja').doc(doc.id).update(data);
                }

                if (imageFile != null && oldFotoUrl.isNotEmpty && oldFotoUrl != fotoUrl) {
                  try {
                    await FirebaseStorage.instance.refFromURL(oldFotoUrl).delete();
                  } catch (e) {
                    debugPrint("Foto aset lama gagal dibersihkan: $e");
                  }
                }

                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _showSnack(doc == null ? "Aset berhasil ditambahkan." : "Aset berhasil diperbarui.");
              } catch (e) {
                if (uploadedRef != null) {
                  try {
                    await uploadedRef.delete();
                  } catch (_) {}
                }
                _showSnack("Gagal menyimpan aset. Data lama tetap dipertahankan.", color: Colors.red);
                if (dialogContext.mounted) setStateDialog(() => saving = false);
              }
            }

            return AlertDialog(
              title: Text(doc == null ? "Tambah Aset" : "Edit Aset"),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: saving ? null : () async {
                          final pickedFile = await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 1600,
                            imageQuality: 75,
                          );
                          if (pickedFile != null && dialogContext.mounted) {
                            setStateDialog(() => imageFile = File(pickedFile.path));
                          }
                        },
                        child: Container(
                          height: 120,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[400]!),
                          ),
                          child: imageFile != null
                              ? Image.file(imageFile!, fit: BoxFit.cover)
                              : fotoUrl.isNotEmpty
                                  ? Image.network(
                                      fotoUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Center(
                                        child: Icon(Icons.broken_image, color: Colors.grey),
                                      ),
                                    )
                                  : const Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.add_a_photo, color: Colors.grey),
                                          SizedBox(height: 4),
                                          Text("Pilih Foto Aset", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: namaController,
                        enabled: !saving,
                        decoration: const InputDecoration(labelText: 'Nama Aset'),
                        validator: (val) => (val ?? '').trim().isEmpty ? 'Nama aset wajib diisi' : null,
                      ),
                      TextFormField(
                        controller: kategoriController,
                        enabled: !saving,
                        decoration: const InputDecoration(labelText: 'Kategori'),
                        validator: (val) => (val ?? '').trim().isEmpty ? 'Kategori wajib diisi' : null,
                      ),
                      TextFormField(
                        controller: jumlahController,
                        enabled: !saving,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Jumlah Unit'),
                        validator: (val) {
                          final number = int.tryParse((val ?? '').trim());
                          if (number == null || number <= 0) return 'Jumlah harus lebih dari 0';
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: lokasiController,
                        enabled: !saving,
                        decoration: const InputDecoration(labelText: 'Lokasi'),
                        validator: (val) => (val ?? '').trim().isEmpty ? 'Lokasi wajib diisi' : null,
                      ),
                      DropdownButtonFormField<String>(
                        value: status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: const ['Baik', 'Rusak Ringan', 'Rusak Berat']
                            .map((label) => DropdownMenuItem(value: label, child: Text(label)))
                            .toList(),
                        onChanged: saving ? null : (val) {
                          if (val != null) setStateDialog(() => status = val);
                        },
                      ),
                      TextFormField(
                        controller: keteranganController,
                        enabled: !saving,
                        decoration: const InputDecoration(labelText: 'Keterangan (Opsional)'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: saving ? null : save,
                  child: saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    namaController.dispose();
    kategoriController.dispose();
    jumlahController.dispose();
    lokasiController.dispose();
    keteranganController.dispose();
  }

  void _confirmDelete(String docId, String? fotoUrl) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus Aset"),
        content: const Text("Apakah Anda yakin ingin menghapus aset ini?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              await _firestore.collection('aset_gereja').doc(docId).delete();
              if (fotoUrl != null && fotoUrl.isNotEmpty) {
                try {
                  await FirebaseStorage.instance.refFromURL(fotoUrl).delete();
                } catch (_) {}
              }
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Aset - ${widget.namaGereja}"),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: UserManager().isAdmin()
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF1A237E),
              onPressed: () => _showAsetDialog(),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Cari nama aset, kategori, atau lokasi...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('aset_gereja')
                  .where('gerejaId', isEqualTo: widget.gerejaId)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Penting: tampilkan error asli dari Firestore.
                // Tanpa ini, error index/permission akan membuat data
                // terlihat "berkedip lalu hilang" karena jatuh ke
                // kondisi hasData == false di bawah.
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        "Gagal memuat data aset:\n${snapshot.error}",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                      child: Text("Belum ada data aset untuk gereja ini."));
                }

                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final nama =
                      (data['nama_aset'] ?? '').toString().toLowerCase();
                  final kategori =
                      (data['kategori'] ?? '').toString().toLowerCase();
                  final lokasi =
                      (data['lokasi'] ?? '').toString().toLowerCase();
                  return nama.contains(_searchQuery) ||
                      kategori.contains(_searchQuery) ||
                      lokasi.contains(_searchQuery);
                }).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text("Aset tidak ditemukan."));
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final namaAset = data['nama_aset'] ?? '';
                    final kategori = data['kategori'] ?? '';
                    final jumlah = data['jumlah'] ?? 0;
                    final lokasi = data['lokasi'] ?? '';
                    final status = data['status'] ?? 'Baik';
                    final keterangan = data['keterangan'] ?? '';
                    final fotoUrl = data['foto_url'] ?? '';

                    Color statusColor = Colors.green;
                    if (status == 'Rusak Ringan') statusColor = Colors.orange;
                    if (status == 'Rusak Berat') statusColor = Colors.red;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: fotoUrl.isNotEmpty
                                  ? Image.network(
                                      fotoUrl,
                                      width: 70,
                                      height: 70,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      width: 70,
                                      height: 70,
                                      color: Colors.grey[300],
                                      child: const Icon(Icons.image,
                                          color: Colors.grey),
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          namaAset,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          status,
                                          style: TextStyle(
                                            color: statusColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.category,
                                          size: 13, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text("$kategori ($jumlah Unit)",
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black87)),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on,
                                          size: 13, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          lokasi,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black87),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (keterangan.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      "Ket: $keterangan",
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                          fontStyle: FontStyle.italic),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (UserManager().isAdmin()) ...[
                                        InkWell(
                                          onTap: () =>
                                              _showAsetDialog(doc: doc),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            child: Row(
                                              children: [
                                                Icon(Icons.edit,
                                                    size: 14,
                                                    color: Colors.blue),
                                                SizedBox(width: 3),
                                                Text("Edit",
                                                    style: TextStyle(
                                                        color: Colors.blue,
                                                        fontSize: 11)),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        InkWell(
                                          onTap: () =>
                                              _confirmDelete(doc.id, fotoUrl),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete,
                                                    size: 14,
                                                    color: Colors.red),
                                                SizedBox(width: 3),
                                                Text("Hapus",
                                                    style: TextStyle(
                                                        color: Colors.red,
                                                        fontSize: 11)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
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
    );
  }
}
