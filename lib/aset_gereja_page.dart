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

  void _showAsetDialog({DocumentSnapshot? doc}) {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController _namaController = TextEditingController(
      text: doc != null ? doc['nama_aset'] ?? '' : '',
    );
    final TextEditingController _kategoriController = TextEditingController(
      text: doc != null ? doc['kategori'] ?? '' : '',
    );
    final TextEditingController _jumlahController = TextEditingController(
      text: doc != null ? doc['jumlah']?.toString() ?? '' : '',
    );
    final TextEditingController _lokasiController = TextEditingController(
      text: doc != null ? doc['lokasi'] ?? '' : '',
    );
    final TextEditingController _keteranganController = TextEditingController(
      text: doc != null ? doc['keterangan'] ?? '' : '',
    );
    
    String? _status = doc != null ? doc['status'] ?? 'Baik' : 'Baik';
    String? _fotoUrl = doc != null ? doc['foto_url'] : null;
    File? _imageFile;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(doc == null ? "Tambah Aset" : "Edit Aset"),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final picker = ImagePicker();
                          final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                          if (pickedFile != null) {
                            setStateDialog(() {
                              _imageFile = File(pickedFile.path);
                            });
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
                          child: _imageFile != null
                              ? Image.file(_imageFile!, fit: BoxFit.cover)
                              : _fotoUrl != null && _fotoUrl!.isNotEmpty
                                  ? Image.network(_fotoUrl!, fit: BoxFit.cover)
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
                        controller: _namaController,
                        decoration: const InputDecoration(labelText: 'Nama Aset'),
                        validator: (val) => val!.isEmpty ? 'Nama aset wajib diisi' : null,
                      ),
                      TextFormField(
                        controller: _kategoriController,
                        decoration: const InputDecoration(labelText: 'Kategori'),
                        validator: (val) => val!.isEmpty ? 'Kategori wajib diisi' : null,
                      ),
                      TextFormField(
                        controller: _jumlahController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Jumlah Unit'),
                        validator: (val) => val!.isEmpty ? 'Jumlah wajib diisi' : null,
                      ),
                      TextFormField(
                        controller: _lokasiController,
                        decoration: const InputDecoration(labelText: 'Lokasi'),
                        validator: (val) => val!.isEmpty ? 'Lokasi wajib diisi' : null,
                      ),
                      DropdownButtonFormField<String>(
                        value: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: ['Baik', 'Rusak Ringan', 'Rusak Berat']
                            .map((label) => DropdownMenuItem(value: label, child: Text(label)))
                            .toList(),
                        onChanged: (val) {
                          setStateDialog(() {
                            _status = val;
                          });
                        },
                      ),
                      TextFormField(
                        controller: _keteranganController,
                        decoration: const InputDecoration(labelText: 'Keterangan (Opsional)'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      Navigator.pop(context);
                      
                      String? downloadUrl = _fotoUrl;
                      if (_imageFile != null) {
                        final ref = FirebaseStorage.instance
                            .ref()
                            .child('aset_gereja')
                            .child('${DateTime.now().millisecondsSinceEpoch}.jpg');
                        await ref.putFile(_imageFile!);
                        downloadUrl = await ref.getDownloadURL();
                      }

                      final data = {
                        'gerejaId': widget.gerejaId, 
                        'nama_aset': _namaController.text.trim(),
                        'kategori': _kategoriController.text.trim(),
                        'jumlah': int.tryParse(_jumlahController.text) ?? 1,
                        'lokasi': _lokasiController.text.trim(),
                        'status': _status,
                        'keterangan': _keteranganController.text.trim(),
                        'foto_url': downloadUrl ?? '',
                        'createdAt': doc == null ? FieldValue.serverTimestamp() : doc['createdAt'],
                      };

                      if (doc == null) {
                        await _firestore.collection('aset_gereja').add(data);
                      } else {
                        await _firestore.collection('aset_gereja').doc(doc.id).update(data);
                      }
                    }
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
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
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("Belum ada data aset untuk gereja ini."));
                }

                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final nama = (data['nama_aset'] ?? '').toLowerCase();
                  final kategori = (data['kategori'] ?? '').toLowerCase();
                  final lokasi = (data['lokasi'] ?? '').toLowerCase();
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
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                                      child: const Icon(Icons.image, color: Colors.grey),
                                    ),
                            ),
                            const SizedBox(width: 10),
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
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
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
                                      const Icon(Icons.category, size: 13, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text("$kategori ($jumlah Unit)",
                                          style: const TextStyle(fontSize: 12, color: Colors.black87)),
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
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (UserManager().isAdmin()) ...[
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
      floatingActionButton: UserManager().isAdmin()
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text("Tambah Aset"),
              onPressed: () => _showAsetDialog(),
            )
          : null,
    );
  }
}