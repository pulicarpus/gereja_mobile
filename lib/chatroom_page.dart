import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:convert';
import 'dart:io';

import 'secrets.dart'; // Abaikan jika merah di Acode
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
  
  // --- MESIN VN ---
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  String? _playingId;

  late String _collectionPath;
  bool _isTyping = false;
  bool _isUploading = false;
  
  // --- STATE UNTUK REPLY / EDIT ---
  Map<String, dynamic>? _replyMessage;
  String? _editingMessageId;

  // --- KUNCI RAHASIA ---
  final String teleBotToken = teleBotTokenSecret;
  final String teleChatId = "-1003815632729";
  final String osRestKey = osRestKeySecret;
  final String osAppId = "a9ff250a-56ef-413d-b825-67288008d614";

  @override
  void initState() {
    super.initState();
    _collectionPath = widget.filterKategorial == null ? "chats" : "chats_${widget.filterKategorial}";
    _etPesan.addListener(() => setState(() => _isTyping = _etPesan.text.trim().isNotEmpty));
    
    // Reset player saat audio selesai diputar
    _audioPlayer.onPlayerComplete.listen((event) {
      setState(() => _playingId = null);
    });
  }

  @override
  void dispose() {
    _etPesan.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ==== 1. FORMAT WAKTU CERDAS ====
  String formatTimeCustom(DateTime? date) {
    if (date == null) return "";
    final sekarang = DateTime.now();
    final isHariIni = sekarang.year == date.year && sekarang.month == date.month && sekarang.day == date.day;
    return isHariIni ? DateFormat('HH:mm').format(date) : DateFormat('dd MMM, HH:mm').format(date);
  }

  // ==== 2. UPLOAD GAMBAR KE CLOUDINARY ====
  Future<void> _uploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 60);
    if (image == null) return;

    setState(() => _isUploading = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse('https://api.cloudinary.com/v1_1/dw1ynjbod/image/upload'));
      request.fields['upload_preset'] = 'preset_gereja'; // Preset Unsigned
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      var res = await request.send();
      var json = jsonDecode(await res.stream.bytesToString());

      if (res.statusCode == 200) {
        _sendToFirestore(isi: "[Gambar]", tipe: "image", url: json['secure_url'], name: "img.jpg", cloudId: json['public_id']);
      } else {
        _showSnack("Cloudinary Error: ${json['error']?['message']}");
      }
    } catch (e) {
      _showSnack("Gagal kirim gambar: $e");
    } finally {
      setState(() => _isUploading = false);
    }
  }

  // ==== 3. UPLOAD FILE KE TELEGRAM ====
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
      var jsonRes = jsonDecode(await res.stream.bytesToString());

      if (res.statusCode == 200) {
        String fileId = jsonRes['result']['document']['file_id'];
        var getFile = await http.get(Uri.parse('https://api.telegram.org/bot$teleBotToken/getFile?file_id=$fileId'));
        String filePath = jsonDecode(getFile.body)['result']['file_path'];
        
        _sendToFirestore(isi: fileName, tipe: "file", url: "https://api.telegram.org/file/bot$teleBotToken/$filePath", name: fileName);
      }
    } catch (e) {
      _showSnack("Gagal kirim file: $e");
    } finally {
      setState(() => _isUploading = false);
    }
  }

  // ==== 4. LOGIKA VOICE NOTE (REKAM & UPLOAD) ====
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/vn_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() => _isRecording = true);
      }
    } catch (e) { _showSnack("Gagal merekam: $e"); }
  }

  Future<void> _stopRecording() async {
    final path = await _audioRecorder.stop();
    setState(() => _isRecording = false);
    if (path != null) {
      _uploadVN(File(path));
    }
  }

  Future<void> _uploadVN(File file) async {
    setState(() => _isUploading = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse('https://api.telegram.org/bot$teleBotToken/sendAudio'));
      request.fields['chat_id'] = teleChatId;
      request.files.add(await http.MultipartFile.fromPath('audio', file.path));
      
      var res = await request.send();
      var jsonRes = jsonDecode(await res.stream.bytesToString());

      if (res.statusCode == 200) {
        String fileId = jsonRes['result']['audio']['file_id'];
        var getFile = await http.get(Uri.parse('https://api.telegram.org/bot$teleBotToken/getFile?file_id=$fileId'));
        String filePath = jsonDecode(getFile.body)['result']['file_path'];
        String url = "https://api.telegram.org/file/bot$teleBotToken/$filePath";
        
        _sendToFirestore(isi: "[Voice Note]", tipe: "audio", url: url);
      }
    } catch (e) { _showSnack("Gagal kirim VN: $e"); }
    finally { setState(() => _isUploading = false); }
  }

  Future<void> _playAudio(String url, String id) async {
    if (_playingId == id) {
      await _audioPlayer.pause();
      setState(() => _playingId = null);
    } else {
      await _audioPlayer.play(UrlSource(url));
      setState(() => _playingId = id);
    }
  }

  // ==== 5. BUKA DOKUMEN (WPS / WORD) ====
  Future<void> _bukaFile(String url, String fileName) async {
    _showSnack("Mengunduh dokumen...");
    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/$fileName';
      final file = File(savePath);

      if (!await file.exists()) {
        var response = await http.get(Uri.parse(url));
        await file.writeAsBytes(response.bodyBytes);
      }

      final result = await OpenFilex.open(savePath);
      if (result.type != ResultType.done) {
        _showSnack("Tidak ada aplikasi untuk membuka file ini.");
      }
    } catch (e) {
      _showSnack("Gagal membuka dokumen: $e");
    }
  }

  // ==== 6. SIMPAN FIRESTORE (Kirim Baru, Edit, & Balas) ====
  Future<void> _sendToFirestore({required String isi, required String tipe, String? url, String? name, String? cloudId}) async {
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) return;

    if (_editingMessageId != null) {
      await _db.collection("churches").doc(churchId).collection(_collectionPath).doc(_editingMessageId).update({"pesan": "$isi (diedit)"});
      setState(() { _editingMessageId = null; _etPesan.clear(); });
      return;
    }

    _kirimNotif(isi);
    setState(() { _replyMessage = null; _etPesan.clear(); });
  }

  // ==== 7. NOTIFIKASI ONESIGNAL ====
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

  // ==== 8. UI BANTUAN ====
  void _showFullImage(String url) {
    showDialog(context: context, builder: (c) => Dialog(
      backgroundColor: Colors.transparent, insetPadding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain)),
          Positioned(top: 40, right: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.pop(c)))
        ],
      ),
    ));
  }

  void _deleteMessage(String id) async {
    String? churchId = UserManager().activeChurchId;
    if (churchId != null) await _db.collection("churches").doc(churchId).collection(_collectionPath).doc(id).delete();
  }

  void _showChatMenu(Map<String, dynamic> chat, String docId) {
    bool isMe = chat['pengirimId'] == _auth.currentUser?.uid;
    bool isAdmin = UserManager().isAdmin();

    showModalBottomSheet(context: context, builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.reply), title: const Text("Balas"), onTap: () {
            Navigator.pop(context); setState(() { _replyMessage = chat; _editingMessageId = null; });
          }),
          if (isMe && chat['tipe'] == 'text')
            ListTile(leading: const Icon(Icons.edit), title: const Text("Edit Pesan"), onTap: () {
              Navigator.pop(context); setState(() { _editingMessageId = docId; _replyMessage = null; _etPesan.text = chat['pesan'].replaceAll(" (diedit)", ""); });
            }),
          if (isMe || isAdmin)
            ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("Hapus", style: TextStyle(color: Colors.red)), onTap: () {
              Navigator.pop(context); _deleteMessage(docId);
            }),
        ],
      ),
    ));
  }

  void _showSnack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  void _showPickerOptions() {
    showModalBottomSheet(context: context, builder: (c) => SafeArea(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(leading: const Icon(Icons.image, color: Colors.blue), title: const Text("Gambar"), onTap: () { Navigator.pop(context); _uploadImage(); }),
        ListTile(leading: const Icon(Icons.file_present, color: Colors.orange), title: const Text("Dokumen"), onTap: () { Navigator.pop(context); _uploadFile(); }),
      ],
    )));
  }

  // ==== 9. WIDGET BUILDER ====
  @override
  Widget build(BuildContext context) {
    String? churchId = UserManager().activeChurchId;
    return Scaffold(
      backgroundColor: Colors.blueGrey[50],
      appBar: AppBar(title: Text(widget.filterKategorial ?? "Chat Jemaat"), backgroundColor: Colors.indigo[900], foregroundColor: Colors.white),
      body: Column(
        children: [
          if (_isUploading) const LinearProgressIndicator(backgroundColor: Colors.orange, color: Colors.white),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection("churches").doc(churchId).collection(_collectionPath).orderBy("timestamp", descending: true).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                var docs = snap.data!.docs;
                return ListView.builder(
                  reverse: true, padding: const EdgeInsets.all(10), itemCount: docs.length,
                  itemBuilder: (context, i) {
                    var chat = docs[i].data() as Map<String, dynamic>;
                    String docId = docs[i].id;
                    return _buildChatBubble(chat, docId, chat['pengirimId'] == _auth.currentUser?.uid);
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

  Widget _buildChatBubble(Map<String, dynamic> chat, String docId, bool isMe) {
    String tipe = chat['tipe'] ?? 'text';
    DateTime? waktu = (chat['timestamp'] as Timestamp?)?.toDate();

    return GestureDetector(
      onLongPress: () => _showChatMenu(chat, docId),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe) Padding(
            padding: const EdgeInsets.only(left: 45, bottom: 2), 
            child: Text(chat['pengirimNama'] ?? "Jemaat", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey))
          ),
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) CircleAvatar(radius: 16, backgroundColor: Colors.indigo[100], backgroundImage: chat['pengirimFoto'] != null ? CachedNetworkImageProvider(chat['pengirimFoto']) : null, child: chat['pengirimFoto'] == null ? const Icon(Icons.person, size: 16) : null),
              
              Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isMe ? Colors.indigo[700] : Colors.white,
                  borderRadius: BorderRadius.only(topLeft: const Radius.circular(15), topRight: const Radius.circular(15), bottomLeft: Radius.circular(isMe ? 15 : 0), bottomRight: Radius.circular(isMe ? 0 : 15)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (chat['isReply'] == true) _buildReplyUI(chat, isMe),
                    
                    if (tipe == 'audio') _buildAudioUI(chat, docId, isMe)
                    else if (tipe == 'image') InkWell(onTap: () => _showFullImage(chat['fileUrl']), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: chat['fileUrl'], fit: BoxFit.cover)))
                    else if (tipe == 'file') InkWell(
                      onTap: () => _bukaFile(chat['fileUrl'], chat['fileName'] ?? "dokumen"), 
                      child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.insert_drive_file, color: Colors.orange, size: 30), const SizedBox(width: 8), Expanded(child: Text(chat['fileName'] ?? "File", style: TextStyle(color: isMe ? Colors.white : Colors.indigo, decoration: TextDecoration.underline)))])
                    )
                    else Text(chat['pesan'] ?? "", style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 15)),
                    
                    const SizedBox(height: 4),
                    Align(alignment: Alignment.bottomRight, child: Text(formatTimeCustom(waktu), style: TextStyle(fontSize: 9, color: isMe ? Colors.white70 : Colors.grey))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAudioUI(Map<String, dynamic> chat, String id, bool isMe) {
    bool isPlaying = _playingId == id;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle, color: isMe ? Colors.white : Colors.indigo, size: 35),
          onPressed: () => _playAudio(chat['fileUrl'], id),
        ),
        Row(children: List.generate(10, (index) => Container(
          width: 3, height: isPlaying ? (10.0 + (index % 3 * 5)) : 15.0, 
          margin: const EdgeInsets.symmetric(horizontal: 1), 
          decoration: BoxDecoration(color: isMe ? Colors.white54 : Colors.black12, borderRadius: BorderRadius.circular(2)),
        ))),
      ],
    );
  }

  Widget _buildReplyUI(Map<String, dynamic> chat, bool isMe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5), padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(5), border: Border(left: BorderSide(color: isMe ? Colors.white : Colors.indigo, width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(chat['replyToName'] ?? "", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: isMe ? Colors.white : Colors.indigo)),
        Text(chat['replyToText'] ?? "", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
      ]),
    );
  }

  Widget _buildInputArea() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // PREVIEW REPLY / EDIT
          if (_replyMessage != null || _editingMessageId != null) Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), color: Colors.grey[200],
            child: Row(
              children: [
                Icon(_editingMessageId != null ? Icons.edit : Icons.reply, color: Colors.indigo),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_editingMessageId != null ? "Edit Pesan" : "Membalas ${_replyMessage?['pengirimNama']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
                  Text(_editingMessageId != null ? "Ketik ulang pesan" : (_replyMessage?['pesan'] ?? ""), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                ])),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => setState(() { _replyMessage = null; _editingMessageId = null; _etPesan.clear(); }))
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.indigo, size: 28), onPressed: () => _showPickerOptions()),
                Expanded(child: TextField(controller: _etPesan, maxLines: null, decoration: InputDecoration(hintText: "Ketik pesan...", filled: true, fillColor: Colors.grey[100], contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none)))),
                const SizedBox(width: 5),
                // --- TOMBOL MIC / SEND ---
                GestureDetector(
                  onLongPressStart: (_) { if (!_isTyping) _startRecording(); },
                  onLongPressEnd: (_) { if (!_isTyping) _stopRecording(); },
                  child: CircleAvatar(
                    radius: 24, backgroundColor: _isRecording ? Colors.red : Colors.indigo[900],
                    child: IconButton(
                      icon: Icon(_isTyping ? Icons.send : Icons.mic, color: Colors.white),
                      onPressed: () { if (_isTyping) _sendToFirestore(isi: _etPesan.text.trim(), tipe: "text"); },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}