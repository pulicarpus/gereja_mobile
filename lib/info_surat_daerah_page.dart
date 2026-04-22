import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'user_manager.dart';

class InfoSuratDaerahPage extends StatefulWidget {
  final String namaDaerah;

  const InfoSuratDaerahPage({super.key, required this.namaDaerah});

  @override
  State<InfoSuratDaerahPage> createState() => _InfoSuratDaerahPageState();
}

class _InfoSuratDaerahPageState extends State<InfoSuratDaerahPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final UserManager _user = UserManager();
  
  bool _isLoading = false;

  bool get _canEdit {
    return _user.isSuperAdmin() || (_user.isAdminDaerah() && _user.adminDaerahArea == widget.namaDaerah);
  }

  void _showAddPostDialog() {
    final txtJudul = TextEditingController();
    final txtIsi = TextEditingController();
    String kategori = "Pengumuman";
    File? imageFile;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Buat Postingan Baru", style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: kategori,
                  decoration: const InputDecoration(labelText: "Kategori", border: OutlineInputBorder()),
                  items: ["Pengumuman", "Surat Resmi"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (val) => setStateDialog(() => kategori = val!),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: txtJudul,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: "Judul", hintText: "Cth: Undangan Rapat", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: txtIsi,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: "Isi Pesan", hintText: "Tulis detail pesan di sini...", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 15),
                
                const Text("Lampiran (Opsional)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 5),
                InkWell(
                  onTap: () async {
                    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75);
                    if (picked != null) {
                      setStateDialog(() => imageFile = File(picked.path));
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                      borderRadius: BorderRadius.circular(10)
                    ),
                    child: imageFile == null
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo, color: Colors.grey),
                              SizedBox(height: 5),
                              Text("Ketuk untuk tambah foto/scan surat", style: TextStyle(fontSize: 11, color: Colors.grey))
                            ],
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(imageFile!, fit: BoxFit.cover, width: double.infinity),
                          ),
                  ),
                ),
                if (imageFile != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setStateDialog(() => imageFile = null),
                      child: const Text("Hapus Foto", style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  )
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isLoading ? null : () => Navigator.pop(dialogContext), 
              child: const Text("Batal")
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: _isLoading ? null : () async {
                if (txtJudul.text.trim().isEmpty || txtIsi.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Judul dan Isi harus diisi!"), backgroundColor: Colors.orange));
                  return;
                }

                setState(() => _isLoading = true);
                setStateDialog(() {}); 

                try {
                  String? lampiranUrl;
                  
                  if (imageFile != null) {
                    String fileName = "surat_${DateTime.now().millisecondsSinceEpoch}.jpg";
                    Reference ref = _storage.ref().child("info_daerah/${widget.namaDaerah}/$fileName");
                    await ref.putFile(imageFile!);
                    lampiranUrl = await ref.getDownloadURL();
                  }

                  await _db.collection("info_surat_daerah").add({
                    "daerah": widget.namaDaerah,
                    "kategori": kategori,
                    "judul": txtJudul.text.trim(),
                    "isi": txtIsi.text.trim(),
                    "tanggal": FieldValue.serverTimestamp(),
                    "lampiranUrl": lampiranUrl,
                    "pengirim": _user.userNama ?? "Pengurus Daerah",
                  });

                  if (mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Berhasil diposting!"), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e"), backgroundColor: Colors.red));
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: _isLoading ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("Posting"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text("Info & Surat ${widget.namaDaerah}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            // 👇 FIREBASE INDEX ERROR BYPASS: orderBy() Dihapus 👇
            stream: _db.collection("info_surat_daerah")
                       .where("daerah", isEqualTo: widget.namaDaerah)
                       .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              var docs = snapshot.data?.docs.toList() ?? [];

              // 👇 PENGURUTAN DIAMBIL ALIH FLUTTER AGAR AMAN 👇
              docs.sort((a, b) {
                Timestamp tA = (a.data() as Map<String, dynamic>)['tanggal'] ?? Timestamp.now();
                Timestamp tB = (b.data() as Map<String, dynamic>)['tanggal'] ?? Timestamp.now();
                return tB.compareTo(tA); // Mengurutkan dari terbaru ke terlama
              });

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mark_email_unread_outlined, size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 15),
                      Text("Belum ada pengumuman atau surat.", style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 80),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  var data = docs[index].data() as Map<String, dynamic>;
                  String docId = docs[index].id;
                  
                  bool isSurat = data['kategori'] == "Surat Resmi";
                  String judul = data['judul'] ?? "Tanpa Judul";
                  String isi = data['isi'] ?? "";
                  String pengirim = data['pengirim'] ?? "Pengurus";
                  String? lampiranUrl = data['lampiranUrl'];
                  Timestamp? ts = data['tanggal'] as Timestamp?;
                  String tgl = ts != null ? DateFormat('dd MMM yyyy • HH:mm').format(ts.toDate()) : "Baru saja";

                  return Card(
                    elevation: 3,
                    margin: const EdgeInsets.only(bottom: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isSurat ? Colors.red.shade50 : Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: isSurat ? Colors.red.shade200 : Colors.blue.shade200)
                                ),
                                child: Row(
                                  children: [
                                    Icon(isSurat ? Icons.mail : Icons.campaign, size: 14, color: isSurat ? Colors.red : Colors.blue),
                                    const SizedBox(width: 5),
                                    Text(isSurat ? "SURAT RESMI" : "PENGUMUMAN", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSurat ? Colors.red : Colors.blue)),
                                  ],
                                ),
                              ),
                              Text(tgl, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            ],
                          ),
                          const SizedBox(height: 15),

                          Text(judul, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
                          const SizedBox(height: 8),
                          Text(isi, style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.5)),
                          const SizedBox(height: 15),

                          if (lampiranUrl != null && lampiranUrl.isNotEmpty) ...[
                             const Divider(),
                             InkWell(
                               onTap: () {
                                 Navigator.push(context, MaterialPageRoute(builder: (ctx) => FullScreenImagePage(imageUrl: lampiranUrl, heroTag: docId)));
                               },
                               child: Container(
                                 padding: const EdgeInsets.all(10),
                                 decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                                 child: Row(
                                   children: [
                                     const Icon(Icons.attach_file, color: Colors.indigo),
                                     const SizedBox(width: 10),
                                     const Expanded(child: Text("Lihat Lampiran Edaran", style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold))),
                                     Hero(
                                       tag: docId,
                                       child: ClipRRect(
                                         borderRadius: BorderRadius.circular(5),
                                         child: CachedNetworkImage(imageUrl: lampiranUrl, width: 40, height: 40, fit: BoxFit.cover, placeholder: (context, url) => const CircularProgressIndicator(), errorWidget: (context, url, error) => const Icon(Icons.error)),
                                       ),
                                     )
                                   ],
                                 ),
                               ),
                             ),
                          ],

                          const SizedBox(height: 15),
                          
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.person_pin, size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text("Oleh: $pengirim", style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
                                ],
                              ),
                              if (_canEdit)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  tooltip: "Hapus Postingan",
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text("Hapus Postingan?"),
                                        content: const Text("Tindakan ini tidak dapat dibatalkan."),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                            onPressed: () async {
                                              Navigator.pop(ctx);
                                              await _db.collection("info_surat_daerah").doc(docId).delete();
                                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Dihapus")));
                                            },
                                            child: const Text("Hapus", style: TextStyle(color: Colors.white)),
                                          )
                                        ],
                                      )
                                    );
                                  },
                                )
                            ],
                          )
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          
          if (_isLoading)
            Container(color: Colors.black.withOpacity(0.3), child: const Center(child: CircularProgressIndicator(color: Colors.white))),
        ],
      ),
      
      floatingActionButton: _canEdit 
        ? FloatingActionButton.extended(
            onPressed: _showAddPostDialog,
            backgroundColor: Colors.indigo[900],
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_alert),
            label: const Text("Buat Postingan"),
          )
        : null,
    );
  }
}

class FullScreenImagePage extends StatelessWidget {
  final String imageUrl;
  final String heroTag;

  const FullScreenImagePage({super.key, required this.imageUrl, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, 
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white), elevation: 0),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true, minScale: 0.5, maxScale: 4, 
          child: Hero(
            tag: heroTag,
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain, width: double.infinity, height: double.infinity,
              placeholder: (context, url) => const CircularProgressIndicator(color: Colors.white),
              errorWidget: (context, url, error) => const Icon(Icons.image_not_supported, size: 100, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}