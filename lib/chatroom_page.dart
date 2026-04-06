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
import 'package:record/record.dart';       // 👈 Untuk Rekam
import 'package:audioplayers/audioplayers.dart'; // 👈 Untuk Putar
import 'dart:convert';
import 'dart:io';
import 'dart:async';

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
  
  // --- MESIN VN ---
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  String? _playingId;

  late String _collectionPath;
  bool _isTyping = false;
  bool _isUploading = false;
  Map<String, dynamic>? _replyMessage;
  String? _editingMessageId;

  final String teleBotToken = teleBotTokenSecret;
  final String teleChatId = "-1003815632729";
  final String osRestKey = osRestKeySecret;
  final String osAppId = "a9ff250a-56ef-413d-b825-67288008d614";

  @override
  void initState() {
    super.initState();
    _collectionPath = widget.filterKategorial == null ? "chats" : "chats_${widget.filterKategorial}";
    _etPesan.addListener(() => setState(() => _isTyping = _etPesan.text.trim().isNotEmpty));
    
    // Reset player saat audio selesai
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

  // ==== LOGIKA REKAM VN ====
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

  // ==== UPLOAD VN KE TELEGRAM ====
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

  // ==== PUTAR AUDIO VN ====
  Future<void> _playAudio(String url, String id) async {
    if (_playingId == id) {
      await _audioPlayer.pause();
      setState(() => _playingId = null);
    } else {
      await _audioPlayer.play(UrlSource(url));
      setState(() => _playingId = id);
    }
  }

  // --- (Fungsi Upload Gambar, File, Firestore, Notif, dan BukaFile tetap sama seperti sebelumnya) ---
  // ... (Untuk menyingkat, saya asumsikan Bos sudah punya fungsi-fungsi tersebut) ...

  Future<void> _uploadImage() async { /* Sesuai kode sebelumnya */ }
  Future<void> _uploadFile() async { /* Sesuai kode sebelumnya */ }
  Future<void> _sendToFirestore({required String isi, required String tipe, String? url, String? name, String? cloudId}) async {
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) return;
    if (_editingMessageId != null) {
      await _db.collection("churches").doc(churchId).collection(_collectionPath).doc(_editingMessageId).update({"pesan": "$isi (diedit)"});
      setState(() { _editingMessageId = null; _etPesan.clear(); });
      return;
    }
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
      "isReply": _replyMessage != null,
      "replyToName": _replyMessage?['pengirimNama'],
      "replyToText": _replyMessage?['tipe'] == 'image' ? '[Gambar]' : _replyMessage?['pesan'],
      "replyToImage": _replyMessage?['tipe'] == 'image' ? _replyMessage?['fileUrl'] : null,
    });
    setState(() { _replyMessage = null; _etPesan.clear(); });
  }

  void _showSnack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  String formatTimeCustom(DateTime? date) {
    if (date == null) return "";
    final sekarang = DateTime.now();
    final isHariIni = sekarang.year == date.year && sekarang.month == date.month && sekarang.day == date.day;
    return isHariIni ? DateFormat('HH:mm').format(date) : DateFormat('dd MMM, HH:mm').format(date);
  }

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
    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMe) Padding(padding: const EdgeInsets.only(left: 45, bottom: 2), child: Text(chat['pengirimNama'] ?? "Jemaat", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey))),
        Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) CircleAvatar(radius: 16, backgroundImage: chat['pengirimFoto'] != null ? CachedNetworkImageProvider(chat['pengirimFoto']) : null),
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isMe ? Colors.indigo[700] : Colors.white,
                borderRadius: BorderRadius.only(topLeft: const Radius.circular(15), topRight: const Radius.circular(15), bottomLeft: Radius.circular(isMe ? 15 : 0), bottomRight: Radius.circular(isMe ? 0 : 15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (chat['isReply'] == true) _buildReplyUI(chat, isMe),
                  if (tipe == 'audio') _buildAudioUI(chat, docId, isMe)
                  else if (tipe == 'image') ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: chat['fileUrl']))
                  else Text(chat['pesan'] ?? "", style: TextStyle(color: isMe ? Colors.white : Colors.black87)),
                  
                  Align(alignment: Alignment.bottomRight, child: Text(formatTimeCustom(waktu), style: TextStyle(fontSize: 9, color: isMe ? Colors.white70 : Colors.grey))),
                ],
              ),
            ),
          ],
        ),
      ],
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
        // Visualizer sederhana
        ...List.generate(10, (index) => Container(
          width: 3, height: isPlaying ? (10.0 + (index % 3 * 5)) : 15.0, 
          margin: const EdgeInsets.symmetric(horizontal: 1), 
          decoration: BoxDecoration(color: isMe ? Colors.white54 : Colors.black12, borderRadius: BorderRadius.circular(2)),
        )),
      ],
    );
  }

  Widget _buildReplyUI(Map<String, dynamic> chat, bool isMe) {
    return Container(
      margin: const EdgeInsets.bottom(5), padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(5), border: Border(left: BorderSide(color: isMe ? Colors.white : Colors.indigo, width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(chat['replyToName'] ?? "", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: isMe ? Colors.white : Colors.indigo)),
        Text(chat['replyToText'] ?? "", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
      ]),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8), color: Colors.white,
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.indigo), onPressed: () => _showPickerOptions()),
          Expanded(child: TextField(controller: _etPesan, decoration: InputDecoration(hintText: "Ketik pesan...", filled: true, fillColor: Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none)))),
          const SizedBox(width: 5),
          // --- TOMBOL MIC / KIRIM ---
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
    );
  }

  void _showPickerOptions() {
    showModalBottomSheet(context: context, builder: (c) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(leading: const Icon(Icons.image), title: const Text("Gambar"), onTap: () { Navigator.pop(context); _uploadImage(); }),
        ListTile(leading: const Icon(Icons.file_present), title: const Text("Dokumen"), onTap: () { Navigator.pop(context); _uploadFile(); }),
      ],
    ));
  }
}