import 'dart:io';
import 'dart:convert'; // 👈 DITAMBAHKAN UNTUK JSON ENCODE NOTIFIKASI
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart'; 
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart'; 
import 'package:http/http.dart' as http;           
import 'package:open_filex/open_filex.dart';       
import 'user_manager.dart';
import 'secrets.dart'; // 👈 WAJIB IMPORT KUNCI RAHASIA ONESIGNAL BOS

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

  // 👇 GEMBALA & BPJ SEKARANG OTOMATIS BISA EDIT/HAPUS (MASUK ANGGOTA DAERAH) 👇
  bool get _canEdit {
    return _user.isSuperAdmin() || 
           (_user.isAdminDaerah() && _user.adminDaerahArea == widget.namaDaerah) ||
           _user.isGembala() ||
           _user.isBPJ();
  }

  // 👇 FUNGSI TEMBAK NOTIFIKASI EKSKLUSIF (HANYA PENGURUS, GEMBALA, BPJ) 👇
  Future<void> _kirimNotifDaerah(String judul, String kategori) async {
    final String osRestKey = teleBotTokenSecret; // Ambil dari secrets.dart (sesuaikan nama variabel Bos jika beda, misal osRestKeySecret)
    // Catatan: Jika di secrets.dart Bos ada osRestKeySecret khusus, gunakan itu! Di sini saya asumsikan namanya osRestKeySecret.
    final String apiKey = osRestKeySecret; 
    final String osAppId = "a9ff250a-56ef-413d-b825-67288008d614";

    if (apiKey.isEmpty) return;

    try {
      var response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8', 
          'Authorization': 'Basic $apiKey'
        },
        body: jsonEncode({
          "app_id": osAppId,
          // LOGIKA FILTER ONESIGNAL SULTAN:
          // (Daerah ini & Admin) ATAU (Daerah ini & Gembala) ATAU (Daerah ini & BPJ)
          "filters": [
            {"field": "tag", "key": "daerah", "relation": "=", "value": widget.namaDaerah},
            {"field": "tag", "key": "role", "relation": "=", "value": "admin_daerah"},
            {"operator": "OR"},
            {"field": "tag", "key": "daerah", "relation": "=", "value": widget.namaDaerah},
            {"field": "tag", "key": "role", "relation": "=", "value": "gembala"},
            {"operator": "OR"},
            {"field": "tag", "key": "daerah", "relation": "=", "value": widget.namaDaerah},
            {"field": "tag", "key": "role", "relation": "=", "value": "bpj"}
          ],
          "headings": {"en": "📢 Info Daerah: ${widget.namaDaerah}"},
          "contents": {"en": "[$kategori] $judul"},
          "data": {
             "type": "info_daerah",
             "daerah": widget.namaDaerah
          }
        }),
      );
      debugPrint("Notif Daerah Response: ${response.body}");
    } catch (e) {
      debugPrint("ERROR FATAL NOTIF DAERAH: $e");
    }
  }

  Future<File?> _scanDocument() async {
    try {
      DocumentScannerOptions options = DocumentScannerOptions(
        mode: ScannerMode.filter,
        pageLimit: 1,
      );
      DocumentScanner scanner = DocumentScanner(options: options);
      DocumentScanningResult result = await scanner.scanDocument();
      
      if (result.images != null && result.images!.isNotEmpty) {
        return File(result.images!.first);
      }
    } catch (e) {
      debugPrint("Scanner Error: $e");
    }
    return null;
  }

  Future<File?> _pickDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'],
    );
    if (result != null && result.files.single.path != null) {
      return File(result.files.single.path!);
    }
    return null;
  }

  Future<void> _shareToLocalChat(Map<String, dynamic> data) async {
    String? churchId = _user.activeChurchId;
    if (churchId == null) return;

    setState(() => _isLoading = true);
    try {
      String judul = data['judul'] ?? "Info Daerah";
      String isi = data['isi'] ?? "";
      String? link = data['lampiranUrl'];
      String tipe = data['kategori'] ?? "INFO";
      bool isImage = data['isImage'] ?? false;
      String namaFile = data['namaFile'] ?? "Dokumen Lampiran";

      await _db.collection("churches").doc(churchId).collection("chats").add({
        "senderId": _user.userId,
        "senderNama": "📢 PENGURUS DAERAH",
        "pesan": "📌 *[$tipe]*\n\n*${judul.toUpperCase()}*\n$isi", 
        "timestamp": FieldValue.serverTimestamp(),
        "isInfoDaerah": true, 
        "lampiranUrl": link, 
        "isImage": isImage,
        "namaFile": namaFile,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Berhasil dibagikan ke Chatroom Lokal!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Share: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadAndOpenFile(String url, String originalFileName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.indigo),
            SizedBox(width: 15),
            Expanded(child: Text("Membuka dokumen...")),
          ],
        ),
      ),
    );

    try {
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final directory = await getTemporaryDirectory();
        String ext = ".pdf"; 
        if (url.contains(".doc")) ext = ".docx";
        else if (url.contains(".xls")) ext = ".xlsx";
        else if (url.contains(".ppt")) ext = ".pptx";
        
        String filePath = '${directory.path}/Dokumen_GKII_${DateTime.now().millisecondsSinceEpoch}$ext';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        if (mounted) Navigator.pop(context);
        final result = await OpenFilex.open(file.path);
        
        if (result.type != ResultType.done) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tidak ada aplikasi untuk membuka file ini (Coba install WPS/PDF Reader)."), backgroundColor: Colors.orange));
        }
      } else {
        throw Exception("Gagal mengunduh file.");
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Terjadi kesalahan: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _showAddPostDialog() {
    final txtJudul = TextEditingController();
    final txtIsi = TextEditingController();
    String kategori = "Pengumuman";
    File? attachedFile;
    bool isImage = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Postingan Daerah", style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: kategori,
                  decoration: const InputDecoration(labelText: "Kategori", border: OutlineInputBorder()),
                  items: ["Pengumuman", "Surat Resmi"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (val) => setStateDialog(() => kategori = val!),
                ),
                const SizedBox(height: 15),
                TextField(controller: txtJudul, decoration: const InputDecoration(labelText: "Judul", border: OutlineInputBorder())),
                const SizedBox(height: 15),
                TextField(controller: txtIsi, maxLines: 3, decoration: const InputDecoration(labelText: "Isi Pesan", border: OutlineInputBorder())),
                const SizedBox(height: 15),
                
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          File? file = await _scanDocument();
                          if (file != null) setStateDialog(() { attachedFile = file; isImage = true; });
                        },
                        icon: const Icon(Icons.document_scanner, size: 16),
                        label: const Text("Scan", style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade50, foregroundColor: Colors.blue.shade900),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          File? file = await _pickDocument();
                          if (file != null) setStateDialog(() { attachedFile = file; isImage = false; });
                        },
                        icon: const Icon(Icons.upload_file, size: 16),
                        label: const Text("File", style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade50, foregroundColor: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),

                if (attachedFile != null)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        Icon(isImage ? Icons.image : Icons.description, color: Colors.indigo),
                        const SizedBox(width: 10),
                        Expanded(child: Text(attachedFile!.path.split('/').last, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                        IconButton(onPressed: () => setStateDialog(() => attachedFile = null), icon: const Icon(Icons.close, size: 16, color: Colors.red))
                      ],
                    ),
                  )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Batal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: () async {
                if (txtJudul.text.trim().isEmpty) return;
                setState(() => _isLoading = true);
                Navigator.pop(dialogContext);

                try {
                  String? fileUrl;
                  String? fileNameOriginal;

                  if (attachedFile != null) {
                    fileNameOriginal = attachedFile!.path.split('/').last;
                    String ext = attachedFile!.path.split('.').last;
                    String fileName = "doc_${DateTime.now().millisecondsSinceEpoch}.$ext";
                    Reference ref = _storage.ref().child("info_daerah/${widget.namaDaerah}/$fileName");
                    await ref.putFile(attachedFile!);
                    fileUrl = await ref.getDownloadURL();
                  }

                  await _db.collection("info_surat_daerah").add({
                    "daerah": widget.namaDaerah,
                    "kategori": kategori,
                    "judul": txtJudul.text.trim(),
                    "isi": txtIsi.text.trim(),
                    "tanggal": FieldValue.serverTimestamp(),
                    "lampiranUrl": fileUrl,
                    "namaFile": fileNameOriginal, 
                    "pengirim": _user.userNama ?? "Pengurus",
                    "isImage": isImage,
                  });

                  // 👇 TEMBAK NOTIFIKASI SETELAH SUKSES POSTING 👇
                  _kirimNotifDaerah(txtJudul.text.trim(), kategori);

                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Berhasil diposting!")));
                } catch (e) {
                  debugPrint("Error: $e");
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: const Text("Posting"),
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
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white, elevation: 0,
      ),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: _db.collection("info_surat_daerah").where("daerah", isEqualTo: widget.namaDaerah).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              var docs = snapshot.data?.docs.toList() ?? [];
              docs.sort((a, b) {
                Timestamp tA = (a.data() as Map<String, dynamic>)['tanggal'] ?? Timestamp.now();
                Timestamp tB = (b.data() as Map<String, dynamic>)['tanggal'] ?? Timestamp.now();
                return tB.compareTo(tA);
              });

              if (docs.isEmpty) return const Center(child: Text("Belum ada postingan."));

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  var data = docs[index].data() as Map<String, dynamic>;
                  bool isSurat = data['kategori'] == "Surat Resmi";
                  bool isImage = data['isImage'] ?? false;
                  String? url = data['lampiranUrl'];
                  String fileDisplay = data['namaFile'] ?? "Dokumen Lampiran";

                  return Card(
                    margin: const EdgeInsets.only(bottom: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: isSurat ? Colors.red.shade50 : Colors.blue.shade50, borderRadius: BorderRadius.circular(5)),
                                child: Text(data['kategori'].toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isSurat ? Colors.red : Colors.blue)),
                              ),
                              if (_canEdit)
                                Row(
                                  children: [
                                    IconButton(onPressed: () => _shareToLocalChat(data), icon: const Icon(Icons.share, size: 20, color: Colors.green), tooltip: "Share ke Chatroom Lokal"),
                                    IconButton(onPressed: () => _db.collection("info_surat_daerah").doc(docs[index].id).delete(), icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red)),
                                  ],
                                )
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(data['judul'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 5),
                          Text(data['isi'], style: const TextStyle(fontSize: 13, color: Colors.black54)),
                          
                          if (url != null) ...[
                            const SizedBox(height: 15),
                            InkWell(
                              onTap: () async {
                                if (isImage) {
                                  Navigator.push(context, MaterialPageRoute(builder: (c) => FullScreenImagePage(imageUrl: url, heroTag: docs[index].id)));
                                } else {
                                  await _downloadAndOpenFile(url, fileDisplay);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
                                child: Row(
                                  children: [
                                    Icon(isImage ? Icons.image : Icons.description, color: Colors.indigo),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(isImage ? "Lihat Dokumen Scan" : "Buka Dokumen", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 12))),
                                    const Icon(Icons.open_in_new, size: 16, color: Colors.indigo),
                                  ],
                                ),
                              ),
                            )
                          ],
                          const SizedBox(height: 10),
                          Text("Oleh: ${data['pengirim']}", style: const TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          if (_isLoading) Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator())),
        ],
      ),
      floatingActionButton: _canEdit ? FloatingActionButton(onPressed: _showAddPostDialog, backgroundColor: Colors.indigo[900], child: const Icon(Icons.add, color: Colors.white)) : null,
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
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(child: Hero(tag: heroTag, child: CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain))),
    );
  }
}