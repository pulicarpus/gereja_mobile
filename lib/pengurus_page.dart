import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'user_manager.dart';
import 'loading_sultan.dart';
import 'detail_seksi_page.dart';

class PengurusPage extends StatefulWidget {
  final String? churchId; // 👈 DITAMBAHKAN AGAR BISA MENERIMA ID DARI LUAR

  const PengurusPage({super.key, this.churchId});

  @override
  State<PengurusPage> createState() => _PengurusPageState();
}

class _PengurusPageState extends State<PengurusPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final UserManager _userManager = UserManager();
  
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  late String _activeChurchId; // 👈 Variabel penampung ID Gereja yang final

  @override
  void initState() {
    super.initState();
    // Jika ada ID yang dikirim (dari daerah), pakai itu. Jika tidak, pakai gereja lokal user.
    _activeChurchId = widget.churchId ?? _userManager.getChurchIdForCurrentView()!; 
  }

  // 👇 CEK APAKAH USER PUNYA HAK EDIT DI GEREJA INI 👇
  bool _hasEditAccess() {
    if (!_userManager.isAdmin()) return false;
    // SuperAdmin Daerah tidak boleh edit BPJ saat sedang "ngintip"
    if (widget.churchId != null && widget.churchId != _userManager.activeChurchId) return false;
    return true;
  }

  void _bukaWhatsApp(String noWa) async {
    if (noWa.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nomor WA belum diisi oleh Admin.")));
      return;
    }
    
    String cleanWa = noWa.replaceAll(RegExp(r'[-\s+]'), '');
    if (cleanWa.startsWith('0')) cleanWa = '62${cleanWa.substring(1)}';

    final Uri waUrl = Uri.parse("https://wa.me/$cleanWa");
    if (await canLaunchUrl(waUrl)) {
      await launchUrl(waUrl, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tidak dapat membuka WhatsApp")));
    }
  }

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
                  _bukaWhatsApp(wa);      
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

  void _showSeksiNameDialog({String? docId, String initialName = ""}) {
    if (!_hasEditAccess()) return;
    final etSeksi = TextEditingController(text: initialName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(docId == null ? "Tambah Seksi Baru" : "Edit Nama Seksi", style: const TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: etSeksi,
          decoration: const InputDecoration(labelText: "Nama Seksi/Komisi", hintText: "Cth: Pemuda, Kaum Ibu"),
        ),
        actions: [
          if (docId != null) 
            TextButton(
              onPressed: () {
                _db.collection("churches").doc(_activeChurchId).collection("bpj_seksi").doc(docId).delete();
                Navigator.pop(context);
              },
              child: const Text("Hapus", style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            onPressed: () async {
              if (etSeksi.text.trim().isEmpty) return;
              
              if (docId == null) {
                await _db.collection("churches").doc(_activeChurchId).collection("bpj_seksi").add({
                  "namaSeksi": etSeksi.text.trim(),
                });
              } else {
                await _db.collection("churches").doc(_activeChurchId).collection("bpj_seksi").doc(docId).update({
                  "namaSeksi": etSeksi.text.trim(),
                });
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text("Simpan"),
          ),
        ],
      ),
    );
  }

  void _showEditIntiDialog({
    required String title,
    required String roleId, 
    String initialNama = "",
    String initialWa = "",
    String? initialFotoUrl,
  }) {
    if (!_hasEditAccess()) return;

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

                try {
                  if (imageFile != null) {
                    String fileName = "harian_$roleId";
                    Reference ref = _storage.ref().child("gereja/$_activeChurchId/pengurus/$fileName.jpg");
                    await ref.putFile(imageFile!);
                    uploadedUrl = await ref.getDownloadURL();
                  }

                  await _db.collection("churches").doc(_activeChurchId).update({
                    "bpj_$roleId": etNama.text.trim(),
                    "wa_$roleId": etWa.text.trim(),
                    if (uploadedUrl != null) "img_$roleId": uploadedUrl,
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

  Widget _buildGroupCard(String title, List<Widget> members, {VoidCallback? onEditTitle, VoidCallback? onTapCard}) {
    List<Widget> cardContent = [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(15))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade900, fontSize: 14)),
            Row(
              children: [
                if (onEditTitle != null && _hasEditAccess()) 
                  InkWell(onTap: onEditTitle, child: const Padding(padding: EdgeInsets.all(4.0), child: Icon(Icons.edit, size: 18, color: Colors.indigo))),
                if (onTapCard != null)
                  const Padding(padding: EdgeInsets.only(left: 8.0), child: Icon(Icons.chevron_right, color: Colors.indigo)),
              ],
            )
          ],
        ),
      )
    ];

    for (int i = 0; i < members.length; i++) {
      cardContent.add(members[i]);
      if (i < members.length - 1) cardContent.add(Divider(height: 1, indent: 70, color: Colors.grey.shade200));
    }

    return GestureDetector(
      onTap: onTapCard, 
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cardContent),
      ),
    );
  }

  Widget _buildPersonRow(String jabatan, String nama, String? fotoUrl, VoidCallback onTap, VoidCallback onLongPress, {bool showEditIcon = true}) {
    bool isEmpty = nama.isEmpty || nama == "-";
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25, backgroundColor: Colors.indigo.shade50,
              backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty ? CachedNetworkImageProvider(fotoUrl) : null,
              child: fotoUrl == null || fotoUrl.isEmpty ? const Icon(Icons.person, color: Colors.indigo) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(jabatan, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  const SizedBox(height: 4),
                  Text(isEmpty ? "Belum diatur" : nama, style: TextStyle(fontSize: 15, fontWeight: isEmpty ? FontWeight.normal : FontWeight.bold, color: isEmpty ? Colors.grey : Colors.black87, fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal)),
                ],
              ),
            ),
            if (_hasEditAccess() && showEditIcon) const Icon(Icons.edit, size: 16, color: Colors.grey),
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
        title: const Text("Badan Pengurus Jemaat", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white, elevation: 0,
      ),
      body: _isLoading 
        ? const LoadingSultan(size: 80)
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text("PENGURUS INTI", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
                StreamBuilder<DocumentSnapshot>(
                  stream: _db.collection("churches").doc(_activeChurchId).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

                    Widget buildHarianRow(String roleId, String jabatan) {
                      String nama = data["bpj_$roleId"] ?? "";
                      String wa = data["wa_$roleId"] ?? "";
                      String? img = data["img_$roleId"];
                      return _buildPersonRow(
                        jabatan, nama, img,
                        () {
                           if (nama.isEmpty && _hasEditAccess()) {
                              _showEditIntiDialog(title: "Edit $jabatan", roleId: roleId, initialNama: nama, initialWa: wa, initialFotoUrl: img);
                           } else if (nama.isNotEmpty) {
                              _showDetailBottomSheet(nama, jabatan, img, wa, "inti_$roleId");
                           }
                        },
                        () => _showEditIntiDialog(title: "Edit $jabatan", roleId: roleId, initialNama: nama, initialWa: wa, initialFotoUrl: img),
                      );
                    }

                    return Column(
                      children: [
                        _buildGroupCard("PIMPINAN", [buildHarianRow("ketua", "KETUA BPJ"), buildHarianRow("wakil", "WAKIL KETUA")]),
                        _buildGroupCard("SEKRETARIAT", [buildHarianRow("sek1", "SEKRETARIS 1"), buildHarianRow("sek2", "SEKRETARIS 2")]),
                        _buildGroupCard("KEBENDAHARAAN", [buildHarianRow("bend1", "BENDAHARA 1"), buildHarianRow("bend2", "BENDAHARA 2")]),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 20),

                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text("SEKSI & KOMISI", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
                StreamBuilder<QuerySnapshot>(
                  stream: _db.collection("churches").doc(_activeChurchId).collection("bpj_seksi").snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    if (snapshot.data!.docs.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text("Belum ada data seksi.", style: TextStyle(color: Colors.grey.shade500))));

                    return Column(
                      children: snapshot.data!.docs.map((doc) {
                        var data = doc.data() as Map<String, dynamic>;
                        String seksiName = data['namaSeksi'] ?? "Seksi";

                        Widget buildSeksiRow(String roleId, String jabatanTitle, String fallbackNama, String? fallbackImg) {
                          String nama = data['${roleId}_nama'] ?? fallbackNama;
                          String? img = data['${roleId}_img'] ?? fallbackImg;
                          
                          return _buildPersonRow(
                            jabatanTitle, nama, img,
                            () {
                               Navigator.push(context, MaterialPageRoute(
                                 builder: (context) => DetailSeksiPage(docId: doc.id, namaSeksi: seksiName)
                               ));
                            },
                            () {
                               Navigator.push(context, MaterialPageRoute(
                                 builder: (context) => DetailSeksiPage(docId: doc.id, namaSeksi: seksiName)
                               ));
                            },
                            showEditIcon: false 
                          );
                        }

                        String oldNama = data['namaPengurus'] ?? "";
                        String? oldImg = data['fotoUrl'];

                        return _buildGroupCard(
                          seksiName,
                          [
                            buildSeksiRow("ketua", "KETUA", oldNama, oldImg),
                          ],
                          onEditTitle: () => _showSeksiNameDialog(docId: doc.id, initialName: seksiName),
                          onTapCard: () {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (context) => DetailSeksiPage(docId: doc.id, namaSeksi: seksiName)
                            ));
                          }
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 80), 
              ],
            ),
          ),
          
      floatingActionButton: _hasEditAccess()
          ? FloatingActionButton.extended(
              onPressed: () => _showSeksiNameDialog(),
              backgroundColor: Colors.indigo,
              icon: const Icon(Icons.add_business, color: Colors.white),
              label: const Text("Tambah Seksi", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }
}