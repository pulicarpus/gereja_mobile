import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'user_manager.dart';
import 'loading_sultan.dart';

class DetailSeksiPage extends StatefulWidget {
  final String docId;
  final String namaSeksi;

  const DetailSeksiPage({super.key, required this.docId, required this.namaSeksi});

  @override
  State<DetailSeksiPage> createState() => _DetailSeksiPageState();
}

class _DetailSeksiPageState extends State<DetailSeksiPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final UserManager _userManager = UserManager();
  final ImagePicker _picker = ImagePicker();
  
  bool _isLoading = false;

  // 👇 FUNGSI BUKA WHATSAPP 👇
  void _bukaWA(BuildContext context, String wa) async {
    if (wa.isEmpty) return;
    String cleanWa = wa.replaceAll(RegExp(r'[-\s+]'), '');
    if (cleanWa.startsWith('0')) cleanWa = '62${cleanWa.substring(1)}';
    final Uri url = Uri.parse("https://wa.me/$cleanWa");
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  // 👇 FITUR FOTO FULLSCREEN SULTAN 👇
  void _showFullScreenImage(String imageUrl, String heroTag) {
    Navigator.push(context, MaterialPageRoute(builder: (context) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
        body: Center(
          child: InteractiveViewer(
            clipBehavior: Clip.none, minScale: 1.0, maxScale: 4.0,
            child: Hero(
              tag: heroTag,
              child: CachedNetworkImage(
                imageUrl: imageUrl, fit: BoxFit.contain, width: double.infinity,
                placeholder: (context, url) => const CircularProgressIndicator(color: Colors.white),
                errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white, size: 50),
              ),
            ),
          ),
        ),
      );
    }));
  }

  // 👇 BOTTOM SHEET DETAIL PENGURUS 👇
  void _showDetailBottomSheet(String nama, String jabatan, String? fotoUrl, String wa, String heroTag) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                if (fotoUrl != null && fotoUrl.isNotEmpty) _showFullScreenImage(fotoUrl, heroTag);
              },
              child: Hero(
                tag: heroTag,
                child: CircleAvatar(
                  radius: 50, backgroundColor: Colors.indigo.shade50,
                  backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty ? CachedNetworkImageProvider(fotoUrl) : null,
                  child: fotoUrl == null || fotoUrl.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.indigo) : null,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(nama, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo)),
            const SizedBox(height: 4),
            Text(jabatan, style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context); 
                  _bukaWA(context, wa);      
                },
                icon: const Icon(Icons.chat),
                label: const Text("Hubungi via WhatsApp", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // 👇 DIALOG EDIT PENGURUS INTI (Ketua, Sek, Bend) 👇
  void _showEditPersonDialog(String title, String roleId, String initialNama, String initialWa, String? initialFotoUrl) {
    if (!_userManager.isAdmin()) return;

    File? imageFile;
    final etNama = TextEditingController(text: initialNama);
    final etWa = TextEditingController(text: initialWa);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                    if (pickedFile != null) setStateDialog(() => imageFile = File(pickedFile.path));
                  },
                  child: CircleAvatar(
                    radius: 40, backgroundColor: Colors.grey.shade200,
                    backgroundImage: imageFile != null 
                        ? FileImage(imageFile!) 
                        : (initialFotoUrl != null && initialFotoUrl.isNotEmpty ? CachedNetworkImageProvider(initialFotoUrl) : null) as ImageProvider?,
                    child: (imageFile == null && (initialFotoUrl == null || initialFotoUrl.isEmpty))
                        ? const Icon(Icons.camera_alt, color: Colors.grey) : null,
                  ),
                ),
                const SizedBox(height: 8),
                const Text("Ketuk foto untuk mengubah", style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 20),
                
                TextField(controller: etNama, decoration: const InputDecoration(labelText: "Nama Pengurus", hintText: "Nama Lengkap")),
                const SizedBox(height: 10),
                TextField(controller: etWa, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Nomor WhatsApp", hintText: "Cth: 08123456789")),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: () async {
                setState(() => _isLoading = true);
                Navigator.pop(context); 

                String? uploadedUrl = initialFotoUrl;
                String churchId = _userManager.getChurchIdForCurrentView()!;

                try {
                  if (imageFile != null) {
                    String fileName = "seksi_${widget.docId}_$roleId";
                    Reference ref = _storage.ref().child("gereja/$churchId/pengurus/$fileName.jpg");
                    await ref.putFile(imageFile!);
                    uploadedUrl = await ref.getDownloadURL();
                  }

                  await _db.collection("churches").doc(churchId).collection("bpj_seksi").doc(widget.docId).update({
                    "${roleId}_nama": etNama.text.trim(),
                    "${roleId}_wa": etWa.text.trim(),
                    "${roleId}_img": uploadedUrl ?? "",
                  });
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data berhasil disimpan!")));
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: const Text("Simpan"),
            ),
          ],
        ),
      ),
    );
  }

  // 👇 DIALOG TAMBAH/EDIT ANGGOTA DENGAN FOTO & WA 👇
  void _showAddEditAnggotaDialog(String churchId, List<dynamic> currentList, {int? indexToEdit}) {
    if (!_userManager.isAdmin()) return;

    File? imageFile;
    
    // Siapkan data kalau lagi mode edit
    Map<String, dynamic> existingData = {};
    if (indexToEdit != null && currentList[indexToEdit] is Map) {
      existingData = Map<String, dynamic>.from(currentList[indexToEdit]);
    } else if (indexToEdit != null && currentList[indexToEdit] is String) {
      // Fallback kalau data lama cuma teks
      existingData = {"nama": currentList[indexToEdit], "wa": "", "img": ""};
    }

    String? initialFotoUrl = existingData['img'];
    final etNama = TextEditingController(text: existingData['nama'] ?? "");
    final etWa = TextEditingController(text: existingData['wa'] ?? "");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(indexToEdit == null ? "Tambah Anggota" : "Edit Anggota", style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                    if (pickedFile != null) setStateDialog(() => imageFile = File(pickedFile.path));
                  },
                  child: CircleAvatar(
                    radius: 40, backgroundColor: Colors.grey.shade200,
                    backgroundImage: imageFile != null 
                        ? FileImage(imageFile!) 
                        : (initialFotoUrl != null && initialFotoUrl.isNotEmpty ? CachedNetworkImageProvider(initialFotoUrl) : null) as ImageProvider?,
                    child: (imageFile == null && (initialFotoUrl == null || initialFotoUrl.isEmpty))
                        ? const Icon(Icons.camera_alt, color: Colors.grey) : null,
                  ),
                ),
                const SizedBox(height: 8),
                const Text("Ketuk foto untuk mengubah", style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 20),
                
                TextField(controller: etNama, decoration: const InputDecoration(labelText: "Nama Anggota", hintText: "Nama Lengkap")),
                const SizedBox(height: 10),
                TextField(controller: etWa, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Nomor WhatsApp", hintText: "Cth: 08123456789")),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: () async {
                if (etNama.text.trim().isEmpty) return;
                
                setState(() => _isLoading = true);
                Navigator.pop(context); 

                String? uploadedUrl = initialFotoUrl;

                try {
                  if (imageFile != null) {
                    String fileName = "anggota_${widget.docId}_${DateTime.now().millisecondsSinceEpoch}";
                    Reference ref = _storage.ref().child("gereja/$churchId/pengurus/$fileName.jpg");
                    await ref.putFile(imageFile!);
                    uploadedUrl = await ref.getDownloadURL();
                  }

                  Map<String, dynamic> newAnggota = {
                    "nama": etNama.text.trim(),
                    "wa": etWa.text.trim(),
                    "img": uploadedUrl ?? "",
                  };

                  List<dynamic> updatedList = List<dynamic>.from(currentList);
                  if (indexToEdit == null) {
                    updatedList.add(newAnggota); // Tambah baru
                  } else {
                    updatedList[indexToEdit] = newAnggota; // Timpa yang lama
                  }

                  await _db.collection("churches").doc(churchId).collection("bpj_seksi").doc(widget.docId).update({
                    "anggota": updatedList
                  });

                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data anggota disimpan!")));
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: const Text("Simpan"),
            ),
          ],
        ),
      ),
    );
  }

  // 👇 FUNGSI HAPUS ANGGOTA 👇
  void _removeAnggota(String churchId, List<dynamic> currentList, int indexToRemove) {
    List<dynamic> newList = List<dynamic>.from(currentList);
    newList.removeAt(indexToRemove);
    _db.collection("churches").doc(churchId).collection("bpj_seksi").doc(widget.docId).update({"anggota": newList});
  }

  // 👇 TILE ORANG (UNTUK KETUA, SEK, BEND) 👇
  Widget _buildPersonTile(String jabatan, String roleId, String nama, String wa, String? img) {
    bool isEmpty = nama.trim().isEmpty;
    bool isAdmin = _userManager.isAdmin();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (isEmpty && isAdmin) {
            _showEditPersonDialog("Edit $jabatan", roleId, nama, wa, img);
          } else if (!isEmpty) {
            _showDetailBottomSheet(nama, "$jabatan ${widget.namaSeksi}", img, wa, "detail_${widget.docId}_$roleId");
          }
        },
        onLongPress: () {
          if (isAdmin) _showEditPersonDialog("Edit $jabatan", roleId, nama, wa, img);
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25, backgroundColor: Colors.indigo.shade50,
                backgroundImage: img != null && img.isNotEmpty ? CachedNetworkImageProvider(img) : null,
                child: img == null || img.isEmpty ? const Icon(Icons.person, color: Colors.indigo) : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(jabatan, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
                    const SizedBox(height: 4),
                    Text(isEmpty ? "Belum diatur" : nama, style: TextStyle(fontSize: 15, fontWeight: isEmpty ? FontWeight.normal : FontWeight.bold, color: isEmpty ? Colors.grey : Colors.black87, fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal)),
                  ],
                ),
              ),
              if (isAdmin) const Icon(Icons.edit, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String churchId = _userManager.getChurchIdForCurrentView()!;
    final bool isAdmin = _userManager.isAdmin();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text("Struktur ${widget.namaSeksi}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white, elevation: 0,
      ),
      body: _isLoading 
        ? const LoadingSultan(size: 80)
        : StreamBuilder<DocumentSnapshot>(
            stream: _db.collection("churches").doc(churchId).collection("bpj_seksi").doc(widget.docId).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

              bool hasSek = data['sek_nama'] != null && data['sek_nama'].toString().trim().isNotEmpty;
              bool hasBend = data['bend_nama'] != null && data['bend_nama'].toString().trim().isNotEmpty;
              List<dynamic> daftarAnggota = data['anggota'] ?? [];

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 1. PENGURUS INTI SEKSI
                  const Text("PENGURUS HARIAN", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 10),
                  
                  _buildPersonTile("KETUA", "ketua", data['ketua_nama'] ?? data['namaPengurus'] ?? "", data['ketua_wa'] ?? data['telepon'] ?? "", data['ketua_img'] ?? data['fotoUrl']),
                  
                  if (hasSek || isAdmin)
                    _buildPersonTile("SEKRETARIS", "sek", data['sek_nama'] ?? "", data['sek_wa'] ?? "", data['sek_img']),
                    
                  if (hasBend || isAdmin)
                    _buildPersonTile("BENDAHARA", "bend", data['bend_nama'] ?? "", data['bend_wa'] ?? "", data['bend_img']),

                  const SizedBox(height: 25),

                  // 2. DAFTAR ANGGOTA
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("ANGGOTA", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                      if (isAdmin)
                        TextButton.icon(
                          onPressed: () => _showAddEditAnggotaDialog(churchId, daftarAnggota),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text("Tambah"),
                        )
                    ],
                  ),
                  const SizedBox(height: 10),
                  
                  if (daftarAnggota.isEmpty)
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("Belum ada anggota.", style: TextStyle(color: Colors.grey, fontSize: 13))))
                  else
                    Column(
                      children: List.generate(daftarAnggota.length, (index) {
                        var item = daftarAnggota[index];
                        // Fallback handling: Ubah string lama jadi map biar tidak error
                        String namaAnggota = item is Map ? (item['nama'] ?? "") : item.toString();
                        String waAnggota = item is Map ? (item['wa'] ?? "") : "";
                        String? imgAnggota = item is Map ? item['img'] : null;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              _showDetailBottomSheet(namaAnggota, "Anggota ${widget.namaSeksi}", imgAnggota, waAnggota, "anggota_${widget.docId}_$index");
                            },
                            onLongPress: () {
                              if (isAdmin) _showAddEditAnggotaDialog(churchId, daftarAnggota, indexToEdit: index);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 25, backgroundColor: Colors.indigo.shade50,
                                    backgroundImage: imgAnggota != null && imgAnggota.isNotEmpty ? CachedNetworkImageProvider(imgAnggota) : null,
                                    child: imgAnggota == null || imgAnggota.isEmpty ? const Icon(Icons.person, color: Colors.indigo) : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(namaAnggota, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                                        const SizedBox(height: 4),
                                        const Text("Anggota", style: TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                  if (isAdmin) ...[
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 18, color: Colors.grey),
                                      onPressed: () => _showAddEditAnggotaDialog(churchId, daftarAnggota, indexToEdit: index),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                      onPressed: () => _removeAnggota(churchId, daftarAnggota, index),
                                    ),
                                  ]
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                ],
              );
            },
          ),
    );
  }
}