import 'upload_support.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'user_manager.dart';
import 'app_safety.dart'; // 👈 PASTIKAN PATH IMPORT INI SESUAI DENGAN LOKASI FILE user_manager.dart ANDA

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
    return value.isEmpty ? 'Baik' : value;
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
    final createRef = _firestore.collection('aset_gereja').doc();

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
                final access = await ChurchWriteAccess.check(widget.gerejaId);
                if (!mounted || !dialogContext.mounted) return;
                if (imageFile != null) {
                  uploadedRef = FirebaseStorage.instance
                      .ref()
                      .child('aset_gereja')
                      .child('${widget.gerejaId}_${DateTime.now().millisecondsSinceEpoch}.jpg');
                  await uploadedRef.putFile(imageFile!, await prepareUpload(imageFile!)).timeout(const Duration(seconds: 30));
                  fotoUrl = await uploadedRef.getDownloadURL().timeout(const Duration(seconds: 20));
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

                await _firestore.runTransaction((tx) async {
                  await access.inTransaction(tx);
                  final target = doc == null ? createRef : _firestore.collection('aset_gereja').doc(doc.id);
                  final fresh = await tx.get(target);
                  if (doc != null && (!fresh.exists || fresh.data()?['gerejaId'] != widget.gerejaId)) {
                    throw StateError('Data aset berubah atau bukan milik gereja aktif.');
                  }
                  access.assertCurrent();
                  if (doc == null) {
                    if (!fresh.exists) tx.set(target, data);
                  } else {
                    tx.update(target, data);
                  }
                }).timeout(const Duration(seconds: 20));

                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _showSnack(doc == null ? "Aset berhasil ditambahkan." : "Aset berhasil diperbarui.");
              } catch (e) {
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
                        items: <String>{'Baik', 'Rusak Ringan', 'Rusak Berat', status}
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

  Future<void> _confirmDelete(String docId, String? fotoUrl) async {
    if (!_canManage) {
      _showSnack("Anda tidak memiliki izin untuk menghapus aset ini.", color: Colors.red);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Hapus Aset"),
        content: const Text("Apakah Anda yakin ingin menghapus aset ini? Tindakan ini tidak dapat dibatalkan."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Hapus"),
          ),
        ],
      ),
    ) ?? false;

    if (!confirmed) return;

    try {
      final access = await ChurchWriteAccess.check(widget.gerejaId);
      final target = _firestore.collection('aset_gereja').doc(docId);
      await _firestore.runTransaction((tx) async {
        await access.inTransaction(tx);
        final fresh = await tx.get(target);
        if (!fresh.exists) return;
        if (fresh.data()?['gerejaId'] != widget.gerejaId) throw StateError('Gereja aset tidak sesuai.');
        access.assertCurrent();
        tx.delete(target);
      }).timeout(const Duration(seconds: 20));
      _showSnack('Aset berhasil dihapus.');
    } catch (e) {
      _showSnack("Gagal menghapus aset.", color: Colors.red);
    }
  }

  Widget _buildSummaryCard(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Text(value.toString(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  void _showImage(String url, String title) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 300,
                  child: Center(child: Text("Foto tidak dapat dimuat.", style: TextStyle(color: Colors.white))),
                ),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.gerejaId.trim().isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Aset Gereja"),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text("Data gereja tidak valid.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Aset - ${widget.namaGereja}"),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: _canManage
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

                final allDocs = snapshot.data!.docs.toList()
                  ..sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    return _sortDate(bData).compareTo(_sortDate(aData));
                  });

                int totalUnit = 0;
                int baik = 0;
                int ringan = 0;
                int berat = 0;
                for (final doc in allDocs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final rawJumlah = data['jumlah'];
                  final jumlah = rawJumlah is num ? rawJumlah.toInt() : int.tryParse(rawJumlah?.toString() ?? '') ?? 0;
                  totalUnit += jumlah;
                  final status = _safeStatus(data['status']);
                  if (status == 'Baik') baik += jumlah;
                  if (status == 'Rusak Ringan') ringan += jumlah;
                  if (status == 'Rusak Berat') berat += jumlah;
                }

                final docs = allDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final nama = (data['nama_aset'] ?? '').toString().toLowerCase();
                  final kategori = (data['kategori'] ?? '').toString().toLowerCase();
                  final lokasi = (data['lokasi'] ?? '').toString().toLowerCase();
                  final status = _safeStatus(data['status']);
                  final matchesSearch = nama.contains(_searchQuery) ||
                      kategori.contains(_searchQuery) ||
                      lokasi.contains(_searchQuery);
                  final matchesStatus = _statusFilter == 'Semua' || status == _statusFilter;
                  return matchesSearch && matchesStatus;
                }).toList();

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                      child: Row(
                        children: [
                          Expanded(child: _buildSummaryCard("Total Unit", totalUnit, Colors.indigo)),
                          const SizedBox(width: 6),
                          Expanded(child: _buildSummaryCard("Baik", baik, Colors.green)),
                          const SizedBox(width: 6),
                          Expanded(child: _buildSummaryCard("Rusak", ringan + berat, Colors.red)),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: ['Semua', 'Baik', 'Rusak Ringan', 'Rusak Berat'].map((label) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: _statusFilter == label,
                              onSelected: (_) => setState(() => _statusFilter = label),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: docs.isEmpty
                          ? const Center(child: Text("Aset tidak ditemukan."))
                          : ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final namaAset = (data['nama_aset'] ?? 'Tanpa Nama').toString();
                    final kategori = (data['kategori'] ?? 'Tanpa Kategori').toString();
                    final rawJumlah = data['jumlah'];
                    final jumlah = rawJumlah is num ? rawJumlah.toInt() : int.tryParse(rawJumlah?.toString() ?? '') ?? 0;
                    final lokasi = (data['lokasi'] ?? '-').toString();
                    final status = _safeStatus(data['status']);
                    final keterangan = (data['keterangan'] ?? '').toString();
                    final fotoUrl = (data['foto_url'] ?? '').toString();

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
                                  ? GestureDetector(
                                      onTap: () => _showImage(fotoUrl, namaAset),
                                      child: Image.network(
                                        fotoUrl,
                                        width: 70,
                                        height: 70,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 70,
                                          height: 70,
                                          color: Colors.grey[300],
                                          child: const Icon(Icons.broken_image, color: Colors.grey),
                                        ),
                                      ),
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
                                      if (_canManage) ...[
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
                        ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

