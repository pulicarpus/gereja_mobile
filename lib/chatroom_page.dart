import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';

import 'user_manager.dart';

class ChatroomPage extends StatefulWidget {
  final String? filterKategorial;
  const ChatroomPage({super.key, this.filterKategorial});

  @override
  State<ChatroomPage> createState() => _ChatroomPageState();
}

class _ChatroomPageState extends State<ChatroomPage> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _etPesan = TextEditingController();
  final _picker = ImagePicker();
  
  late String _collectionPath;
  bool _isTyping = false;
  bool _isUploading = false;

  // --- API CONFIG (Sesuai Data Bos) ---
  final String teleBotToken = "8632837608:AAHzQBShTgNd31OEDLScM-tTQ3i6ImR4XbE";
  final String teleChatId = "-1003815632729";
  final String osAppId = "a9ff250a-56ef-413d-b825-67288008d614";
  final String osRestKey = "os_v2_app_vh7skcsw55at3obfm4uiacgwctohxklw72zurcurxm772cihckdcslgztwftp65s3s4uuv7ivlutx4sphyiwga23t3gkjex5q74kq2y";

  @override
  void initState() {
    super.initState();
    _collectionPath = widget.filterKategorial == null ? "chats" : "chats_${widget.filterKategorial}";
    _etPesan.addListener(() => setState(() => _isTyping = _etPesan.text.trim().isNotEmpty));
  }

  // ==== 1. JURUS CLOUDINARY (UPLOAD GAMBAR) ====
  Future<void> _uploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image == null) return;

    setState(() => _isUploading = true);

    try {
      var request = http.MultipartRequest('POST', Uri.parse('https://api.cloudinary.com/v1_1/dw1ynjbod/image/upload'));
      request.fields['upload_preset'] = 'ml_default'; // Pastikan preset ini 'unsigned' di setting Cloudinary bos
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var json = jsonDecode(responseData);

      if (response.statusCode == 200) {
        _sendToFirestore(
          isi: "[Gambar]",
          tipe: "image",
          url: json['secure_url'],
          name: "img.jpg",
          cloudId: json['public_id'],
        );
      }
    } catch (e) {
      _showError("Gagal upload gambar: $e");
    } finally {
      setState(() => _isUploading = false);
    }
  }

  // ==== 2. JURUS TELEGRAM BOT (UPLOAD DOKUMEN) ====
  Future<void> _uploadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    File file = File(result.files.single.path!);
    String fileName = result.files.single.name;
    setState(() => _isUploading = true);

    try {
      // Step A: Send ke Telegram
      var request = http.MultipartRequest('POST', Uri.parse('https://api.telegram.org/bot$teleBotToken/sendDocument'));
      request.fields['chat_id'] = teleChatId;
      request.files.add(await http.MultipartFile.fromPath('document', file.path));
      
      var res = await request.send();
      var resData = await res.stream.bytesToString();
      var jsonRes = jsonDecode(resData);

      if (res.statusCode == 200) {
        String fileId = jsonRes['result']['document']['file_id'];
        
        // Step B: Ambil Link Download via getFile
        var getFileRes = await http.get(Uri.parse('https://api.telegram.org/bot$teleBotToken/getFile?file_id=$fileId'));
        var jsonPath = jsonDecode(getFileRes.body);
        String filePath = jsonPath['result']['file_path'];
        String finalUrl = "https://api.telegram.org/file/bot$teleBotToken/$filePath";

        _sendToFirestore(isi: fileName, tipe: "file", url: finalUrl, name: fileName);
      }
    } catch (e) {
      _showError("Gagal upload file: $e");
    } finally {
      setState(() => _isUploading = false);
    }
  }

  // ==== 3. SIMPAN KE FIRESTORE ====
  Future<void> _sendToFirestore({
    required String isi,
    required String tipe,
    String? url,
    String? name,
    String? cloudId,
  }) async {
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) return;

    await _db.collection("churches").doc(churchId).collection(_collectionPath).add({
      "pengirimId": _auth.currentUser?.uid,
      "pengirimNama": UserManager().userNama,
      "pengirimFoto": UserManager().userFotoUrl,
      "pesan": isi,
      "timestamp": FieldValue.serverTimestamp(),
      "tipe": tipe,
      "fileUrl": url,
      "fileName": name,
      "cloudPublicId": cloudId,
      "isReply": false,
    });

    _kirimNotif(isi);
    _etPesan.clear();
  }

  // ==== 4. NOTIFIKASI ONESIGNAL ====
  Future<void> _kirimNotif(String pesan) async {
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) return;
    try {
      await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Basic $osRestKey'},
        body: jsonEncode({
          "app_id": osAppId,
          "filters": [
            {"field": "tag", "key": "active_church", "relation": "=", "value": churchId},
            {"operator": "AND"},
            {"field": "tag", "key": "kategori_aktif", "relation": "=", "value": widget.filterKategorial?.replaceAll(" ", "_") ?? "Umum"}
          ],
          "headings": {"en": "Chat dari ${UserManager().userNama}"},
          "contents": {"en": pesan}
        }),
      );
    } catch (_) {}
  }

  void _showError(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    String? churchId = UserManager().activeChurchId;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.filterKategorial ?? "Chat Jemaat"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (_isUploading) const LinearProgressIndicator(color: Colors.amber),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection("churches").doc(churchId).collection(_collectionPath)
                         .orderBy("timestamp", descending: true).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                var docs = snap.data!.docs;
                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    var chat = docs[i].data() as Map<String, dynamic>;
                    bool isMe = chat['pengirimId'] == _auth.currentUser?.uid;
                    return _buildChatBubble(chat, isMe);
                  },
                );
              },
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildChatBubble(Map<String, dynamic> chat, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe ? Colors.indigo[100] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 2)]
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe) Text(chat['pengirimNama'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            
            // Logika Tampilan Tipe Pesan
            if (chat['tipe'] == 'image')
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(chat['fileUrl'], width: 200, height: 200, fit: BoxFit.cover),
              )
            else if (chat['tipe'] == 'file')
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.description, color: Colors.orange),
                  const SizedBox(width: 5),
                  Text(chat['fileName'] ?? "File", style: const TextStyle(decoration: TextDecoration.underline, color: Colors.blue)),
                ],
              )
            else
              Text(chat['pesan'] ?? ""),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.indigo),
            onPressed: () {
              showModalBottomSheet(context: context, builder: (c) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(leading: const Icon(Icons.image), title: const Text("Kirim Gambar"), onTap: () { Navigator.pop(context); _uploadImage(); }),
                  ListTile(leading: const Icon(Icons.file_present), title: const Text("Kirim Dokumen"), onTap: () { Navigator.pop(context); _uploadFile(); }),
                ],
              ));
            },
          ),
          Expanded(
            child: TextField(
              controller: _etPesan,
              decoration: InputDecoration(hintText: "Ketik pesan...", border: OutlineInputBorder(borderRadius: BorderRadius.circular(30))),
            ),
          ),
          const SizedBox(width: 5),
          CircleAvatar(
            backgroundColor: Colors.indigo[900],
            child: IconButton(
              icon: Icon(_isTyping ? Icons.send : Icons.mic, color: Colors.white),
              onPressed: () {
                if (_isTyping) _sendToFirestore(isi: _etPesan.text.trim(), tipe: "text");
              },
            ),
          ),
        ],
      ),
    );
  }
}