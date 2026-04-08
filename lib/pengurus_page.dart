import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'user_manager.dart';

class PengurusPage extends StatefulWidget {
  const PengurusPage({super.key});

  @override
  State<PengurusPage> createState() => _PengurusPageState();
}

class _PengurusPageState extends State<PengurusPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final UserManager _userManager = UserManager();
  
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  // 👇 FUNGSI BUKA WHATSAPP 👇
  void _bukaWhatsApp(String noWa) async {
    if (noWa.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nomor WA belum diisi oleh Admin.")));
      return;
    }
    
    // Bersihkan format nomor WA
    String cleanWa = noWa.replaceAll(RegExp(r'[-\s+]'), '');
    if (cleanWa.startsWith('0')) {
      cleanWa = '62${cleanWa.substring(1)}';
    }

    final Uri waUrl = Uri.parse("https://wa.me/$cleanWa");
    if (await canLaunchUrl(waUrl)) {
      await launchUrl(waUrl, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tidak dapat membuka WhatsApp")));
      }
    }
  }

  // 👇 BOTTOM SHEET DETAIL PENGURUS (DENGAN TOMBOL WA) 👇
  void _showDetailBottomSheet(String nama, String jabatan, String? fotoUrl, String wa) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.indigo.shade50,
              backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty ? CachedNetworkImageProvider(fotoUrl) : null,
              child: fotoUrl == null || fotoUrl.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.indigo) : null,
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
                  Navigator.pop(context); // Tutup bottom sheet
                  _bukaWhatsApp(wa);      // Lempar ke WA
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

  // 👇 DIALOG UNTUK ADMIN EDIT DATA (Harian & Seksi) 👇
  void _showEditDialog({
    required String title,
    required bool isHarian,
    String? roleId, // "ketua", "sekretaris", dsb
    String? docId,  // ID dokumen untuk seksi
    String initialNama = "",
    String initialSeksi = "",
    String initialWa = "",
    String? initialFotoUrl,
  }) {
    if (!_userManager.isAdmin()) return;

    File? imageFile;
    final etNama = TextEditingController(text: initialNama);
    final etSeksi = TextEditingController(text: initialSeksi);
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
                // FOTO PREVIEW & TOMBOL UBAH FOTO
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
                
                if (!isHarian) ...[
                  TextField(controller: etSeksi, decoration: const InputDecoration(labelText: "Nama Seksi", hintText: "Cth: Pemuda, Musik")),
                  const SizedBox(height: 10),
                ],
                TextField(controller: etNama, decoration: const InputDecoration(labelText: "Nama Pengurus", hintText: "Nama Lengkap")),
                const SizedBox(height: 10),
                TextField(controller: etWa, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Nomor WhatsApp", hintText: "Cth: 08123456789")),
              ],
            ),
          ),
          actions: [
            if (!isHarian && docId != null) // Tombol Hapus untuk Seksi
              TextButton(
                onPressed: () {
                  _db.collection("churches").doc(_userManager.getChurchIdForCurrentView()!).collection("bpj_seksi").doc(docId).delete();
                  Navigator.pop(context);
                },
                child: const Text("Hapus", style: TextStyle(color: Colors.red)),
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: () async {
                setState(() => _isLoading = true);
                Navigator.pop(context); // Tutup dialog, munculkan loading di layar utama

                String? uploadedUrl = initialFotoUrl;
                String churchId = _userManager.getChurchIdForCurrentView()!;

                try {
                  // Jika ganti foto, upload ke Storage dulu
                  if (imageFile != null) {
                    String fileName = isHarian ? "harian_$roleId" : "seksi_${DateTime.now().millisecondsSinceEpoch}";
                    Reference ref = _storage.ref().child("gereja/$churchId/pengurus/$fileName.jpg");
                    await ref.putFile(imageFile!);
                    uploadedUrl = await ref.getDownloadURL();
                  }

                  // Simpan Teks & URL Foto ke Database
                  if (isHarian) {
                    await _db.collection("churches").doc(churchId).update({
                      "bpj_$roleId": etNama.text.trim(),
                      "wa_$roleId": etWa.text.trim(),
                      if (uploadedUrl != null) "img_$roleId": uploadedUrl,
                    });
                  } else {
                    DocumentReference ref = docId == null 
                        ? _db.collection("churches").doc(churchId).collection("bpj_seksi").doc()
                        : _db.collection("churches").doc(churchId).collection("bpj_seksi").doc(docId);
                        
                    await ref.set({
                      "id": ref.id,
                      "namaSeksi": etSeksi.text.trim(),
                      "namaPengurus": etNama.text.trim(),
                      "telepon": etWa.text.trim(),
                      "fotoUrl": uploadedUrl ?? "",
                    });
                  }
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

  // 👇 WIDGET KARTU PENGURUS (BISA DIKLIK & DITEKAN LAMA) 👇
  Widget _buildPengurusCard(String nama, String jabatan, String? fotoUrl, String wa, VoidCallback onTap, VoidCallback onLongPress) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,           // Klik biasa = Detail & WA
        onLongPress: onLongPress, // Tekan lama = Edit Admin
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30, backgroundColor: Colors.indigo.shade50,
                backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty ? CachedNetworkImageProvider(fotoUrl) : null,
                child: fotoUrl == null || fotoUrl.isEmpty ? const Icon(Icons.person, color: Colors.indigo) : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(jabatan.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                    const SizedBox(height: 4),
                    Text(nama.isEmpty ? "-" : nama, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ],
                ),
              ),
              if (_userManager.isAdmin()) const Icon(Icons.edit, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String? churchId = _userManager.getChurchIdForCurrentView();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Badan Pengurus Jemaat", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white, elevation: 0,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. BAGIAN PENGURUS HARIAN (BACA DARI DOKUMEN GEREJA)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text("PENGURUS INTI", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                ),
                StreamBuilder<DocumentSnapshot>(
                  stream: _db.collection("churches").doc(churchId).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

                    List<Map<String, dynamic>> harianList = [
                      {"role": "ketua", "jabatan": "KETUA BPJ"},
                      {"role": "wakil", "jabatan": "WAKIL KETUA BPJ"},
                      {"role": "sekretaris", "jabatan": "SEKRETARIS"},
                      {"role": "bendahara", "jabatan": "BENDAHARA"},
                    ];

                    return Column(
                      children: harianList.map((item) {
                        String r = item['role'];
                        String nama = data["bpj_$r"] ?? "-";
                        String wa = data["wa_$r"] ?? "";
                        String? img = data["img_$r"];

                        return _buildPengurusCard(
                          nama, item['jabatan'], img, wa,
                          () => _showDetailBottomSheet(nama, item['jabatan'], img, wa),
                          () => _showEditDialog(title: "Edit ${item['jabatan']}", isHarian: true, roleId: r, initialNama: nama, initialWa: wa, initialFotoUrl: img),
                        );
                      }).toList(),
                    );
                  },
                ),

                const SizedBox(height: 20),

                // 2. BAGIAN SEKSI KATEGORIAL (BACA DARI KOLEKSI bpj_seksi)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text("KETUA SEKSI & KOMISI", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                ),
                StreamBuilder<QuerySnapshot>(
                  stream: _db.collection("churches").doc(churchId).collection("bpj_seksi").snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    
                    if (snapshot.data!.docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Center(child: Text("Belum ada data seksi.", style: TextStyle(color: Colors.grey.shade500))),
                      );
                    }

                    return Column(
                      children: snapshot.data!.docs.map((doc) {
                        var data = doc.data() as Map<String, dynamic>;
                        String nama = data['namaPengurus'] ?? "";
                        String seksi = data['namaSeksi'] ?? "Seksi";
                        String wa = data['telepon'] ?? "";
                        String? img = data['fotoUrl'];

                        return _buildPengurusCard(
                          nama, seksi, img, wa,
                          () => _showDetailBottomSheet(nama, seksi, img, wa),
                          () => _showEditDialog(title: "Edit Seksi", isHarian: false, docId: doc.id, initialSeksi: seksi, initialNama: nama, initialWa: wa, initialFotoUrl: img),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 80), // Jarak untuk Floating Button
              ],
            ),
          ),
          
      // 👇 TOMBOL TAMBAH SEKSI KHUSUS ADMIN 👇
      floatingActionButton: _userManager.isAdmin()
          ? FloatingActionButton.extended(
              onPressed: () => _showEditDialog(title: "Tambah Seksi", isHarian: false),
              backgroundColor: Colors.indigo,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text("Seksi", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }
}