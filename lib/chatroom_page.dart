import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'dart:io';

// 👇 IMPORT BRANKAS RAHASIA (Abaikan jika merah di Acode) 👇
import 'secrets.dart';
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

  // --- AMBIL KUNCI DARI BRANKAS RAHASIA ---
  final String teleBotToken = teleBotTokenSecret;
  final String teleChatId = "-1003815632729";
  final String osRestKey = osRestKeySecret;
  final String osAppId = "a9ff250a-56ef-413d-b825-67288008d614";

  @override
  void initState() {
    super.initState();
    _collectionPath = widget.filterKategorial == null ? "chats" : "chats_${widget.filterKategorial}";
    _etPesan.addListener(() => setState(() => _isTyping = _etPesan.text.trim().isNotEmpty));
  }

  @override
  void dispose() {
    _etPesan.dispose();
    super.dispose();
  }

  // ==== 1. UPLOAD GAMBAR KE CLOUDINARY ====
  Future<void> _uploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 60);
    if (image == null) return;

    setState(() => _isUploading = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse('https://api.cloudinary.com/v1_1/dw1ynjbod/image/upload'));
      request.fields['upload_preset'] = 'preset_gereja';
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      var res = await request.send();
      var resData = await res.stream.bytesToString();
      var json = jsonDecode(resData);

      if (res.statusCode == 200) {
        _sendToFirestore(
          isi: "[Gambar]",
          tipe: "image",
          url: json['secure_url'],
          name: "img.jpg",
          cloudId: json['public_id'],
        );
      }
    } catch (e) {
      _showSnack("Gagal kirim gambar: $e");
    } finally {
      setState(() => _isUploading = false);
    }
  }

  // ==== 2. UPLOAD FILE KE TELEGRAM BOT API ====
  Future<void> _uploadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    File file = File(result.files.single.path!);
    String fileName = result.files.single.name;
    setState(() => _isUploading = true);

    try {
      var request = http.MultipartRequest('POST', Uri.parse('https://api.telegram.org/bot$teleBotToken/sendDocument'));
      request.fields['chat_id'] = teleChatId;
      request.files.add(await http.MultipartFile.fromPath('document', file.path));
      
      var res = await request.send();
      var resData = await res.stream.bytesToString();
      var jsonRes = jsonDecode(resData);

      if (res.statusCode == 200) {
        String fileId = jsonRes['result']['document']['file_id'];
        var getFile = await http.get(Uri.parse('https://api.telegram.org/bot$teleBotToken/getFile?file_id=$fileId'));
        String filePath = jsonDecode(getFile.body)['result']['file_path'];
        
        _sendToFirestore(
          isi: fileName, 
          tipe: "file", 
          url: "https://api.telegram.org/file/bot$teleBotToken/$filePath", 
          name: fileName
        );
      }
    } catch (e) {
      _showSnack("Gagal kirim file: $e");
    } finally {
      setState(() => _isUploading = false);
    }
  }

  // ==== 3. SIMPAN KE FIRESTORE ====
  Future<void> _sendToFirestore({required String isi, required String tipe, String? url, String? name, String? cloudId}) async {
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
    if (churchId == null || osRestKey.isEmpty) return;
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
          "headings": {"en": "Chat: ${UserManager().userNama}"},
          "contents": {"en": pesan}
        }),
      );
    } catch (_) {}
  }

  void _showSnack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    String? churchId = UserManager().activeChurchId;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(widget.filterKategorial ?? "Chat Jemaat"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          if (UserManager().isAdmin()) 
            IconButton(icon: const Icon(Icons.delete_sweep), onPressed: () => _confirmDelete())
        ],
      ),
      body: Column(
        children: [
          if (_isUploading) const LinearProgressIndicator(backgroundColor: Colors.orange, color: Colors.white),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection("churches").doc(churchId).collection(_collectionPath)
                         .orderBy("timestamp", descending: true).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                var docs = snap.data!.docs;
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(10),
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
    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMe) Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 2),
          child: Text(chat['pengirimNama'] ?? "", style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        ),
        Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe ? Colors.indigo[700] : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(15),
              topRight: const Radius.circular(15),
              bottomLeft: Radius.circular(isMe ? 15 : 0),
              bottomRight: Radius.circular(isMe ? 0 : 15),
            ),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))]
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (chat['tipe'] == 'image')
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: chat['fileUrl'],
                    placeholder: (c, u) => const SizedBox(height: 150, child: Center(child: CircularProgressIndicator())),
                    fit: BoxFit.cover,
                  ),
                )
              else if (chat['tipe'] == 'file')
                InkWell(
                  onTap: () {}, // Tambahkan fungsi buka file jika perlu
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.insert_drive_file, color: Colors.orange, size: 30),
                      const SizedBox(width: 8),
                      Expanded(child: Text(chat['fileName'] ?? "File", style: TextStyle(color: isMe ? Colors.white : Colors.indigo, decoration: TextDecoration.underline))),
                    ],
                  ),
                )
              else
                Text(chat['pesan'] ?? "", style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 15)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.black12))),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.indigo, size: 28),
            onPressed: () => _showPickerOptions(),
          ),
          Expanded(
            child: TextField(
              controller: _etPesan,
              maxLines: null,
              decoration: InputDecoration(
                hintText: "Ketik pesan...",
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 5),
          CircleAvatar(
            radius: 24,
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

  void _showPickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.image, color: Colors.blue), title: const Text("Kirim Gambar"), onTap: () { Navigator.pop(context); _uploadImage(); }),
            ListTile(leading: const Icon(Icons.file_present, color: Colors.orange), title: const Text("Kirim Dokumen"), onTap: () { Navigator.pop(context); _uploadFile(); }),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _confirmDelete() {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("Hapus Chat?"),
      content: const Text("Semua pesan akan dihapus permanen dari gereja ini."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("BATAL")),
        TextButton(onPressed: () {
          Navigator.pop(context);
          // Tambahkan fungsi hapus semua chat di sini
        }, child: const Text("HAPUS", style: TextStyle(color: Colors.red))),
      ],
    ));
  }
}