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

  String formatTimeCustom(DateTime? date) {
    if (date == null) return "";
    return DateFormat('HH:mm').format(date);
  }

  // --- 1. FITUR UPLOAD GAMBAR DENGAN CAPTION (UTUH) ---
  Future<void> _uploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 60);
    if (image == null) return;

    final TextEditingController _etCaption = TextEditingController();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Kirim Gambar", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(File(image.path), height: 150, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _etCaption,
              decoration: InputDecoration(
                hintText: "Tambah keterangan...",
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              maxLines: null,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal", style: TextStyle(color: Colors.red))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF075E54), foregroundColor: Colors.white),
            onPressed: () {
              String caption = _etCaption.text.trim();
              Navigator.pop(context);
              _executeImageUpload(image, caption.isEmpty ? "[Gambar]" : caption);
            }, 
            child: const Text("Kirim"),
          ),
        ],
      ),
    );
  }

  Future<void> _executeImageUpload(XFile image, String caption) async {
    setState(() => _isUploading = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse('https://api.cloudinary.com/v1_1/dw1ynjbod/image/upload'));
      request.fields['upload_preset'] = 'preset_gereja'; 
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      var res = await request.send();
      var json = jsonDecode(await res.stream.bytesToString());

      if (res.statusCode == 200) {
        _sendToFirestore(isi: caption, tipe: "image", url: json['secure_url'], name: "img.jpg", cloudId: json['public_id']);
      }
    } catch (e) {
      _showSnack("Gagal upload gambar: $e");
    } finally {
      setState(() => _isUploading = false);
    }
  }

  // --- 2. FITUR UPLOAD FILE DOKUMEN (UTUH) ---
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

  // --- 3. FITUR VOICE NOTE (UTUH V5) ---
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
    if (path != null) { _uploadVN(File(path)); }
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
        _sendToFirestore(isi: "[Voice Note]", tipe: "audio", url: "https://api.telegram.org/file/bot$teleBotToken/$filePath");
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

  // --- 4. LOGIKA FIRESTORE & NOTIFIKASI (UTUH) ---
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
      "replyToText": _replyMessage?['pesan'],
      "replyToImage": (_replyMessage != null && _replyMessage!['tipe'] == 'image') ? _replyMessage!['fileUrl'] : null,
    });

    _kirimNotif(isi);
    setState(() { _replyMessage = null; _etPesan.clear(); });
  }

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

  // --- 5. UI BUILDING (WHATSAPP STYLE) ---
  void _showFullImage(String url) {
    showDialog(context: context, builder: (c) => Dialog(
      backgroundColor: Colors.transparent, insetPadding: EdgeInsets.zero,
      child: Stack( fit: StackFit.expand, children: [
          InteractiveViewer(child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain)),
          Positioned(top: 40, right: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.pop(c)))
        ],
      ),
    ));
  }

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
      await OpenFilex.open(savePath);
    } catch (e) { _showSnack("Gagal membuka file."); }
  }

  void _showChatMenu(Map<String, dynamic> chat, String docId) {
    bool isMe = chat['pengirimId'] == _auth.currentUser?.uid;
    bool isAdmin = UserManager().isAdmin();
    showModalBottomSheet(context: context, builder: (context) => SafeArea(
      child: Column( mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.reply), title: const Text("Balas"), onTap: () {
            Navigator.pop(context); setState(() { _replyMessage = chat; _editingMessageId = null; });
          }),
          if (isMe && chat['tipe'] == 'text')
            ListTile(leading: const Icon(Icons.edit), title: const Text("Edit Pesan"), onTap: () {
              Navigator.pop(context); setState(() { _editingMessageId = docId; _replyMessage = null; _etPesan.text = chat['pesan'].replaceAll(" (diedit)", ""); });
            }),
          if (isMe || isAdmin)
            ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("Hapus", style: TextStyle(color: Colors.red)), onTap: () {
              Navigator.pop(context); 
              _db.collection("churches").doc(UserManager().activeChurchId).collection(_collectionPath).doc(docId).delete();
            }),
        ],
      ),
    ));
  }

  void _showSnack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _showPickerOptions() {
    showModalBottomSheet(context: context, builder: (c) => SafeArea(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.image, color: Colors.blue), title: const Text("Gambar"), onTap: () { Navigator.pop(context); _uploadImage(); }),
        ListTile(leading: const Icon(Icons.file_present, color: Colors.orange), title: const Text("Dokumen"), onTap: () { Navigator.pop(context); _uploadFile(); }),
      ],
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5DDD5), // Background WA
      appBar: AppBar(
        title: Text(widget.filterKategorial ?? "Chat Jemaat"), 
        backgroundColor: const Color(0xFF075E54), 
        foregroundColor: Colors.white,
        actions: [if (_isUploading) const Padding(padding: EdgeInsets.all(15), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))],
      ),
      body: Column( children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection("churches").doc(UserManager().activeChurchId).collection(_collectionPath).orderBy("timestamp", descending: true).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                var docs = snap.data!.docs;
                return ListView.builder(
                  reverse: true, padding: const EdgeInsets.all(10), itemCount: docs.length,
                  itemBuilder: (context, i) {
                    var chat = docs[i].data() as Map<String, dynamic>;
                    return _buildChatBubble(chat, docs[i].id, chat['pengirimId'] == _auth.currentUser?.uid);
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
    DateTime? waktu = (chat['timestamp'] as Timestamp?)?.toDate();
    return GestureDetector(
      onLongPress: () => _showChatMenu(chat, docId),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe) CircleAvatar(radius: 16, backgroundImage: chat['pengirimFoto'] != null ? CachedNetworkImageProvider(chat['pengirimFoto']) : null, child: chat['pengirimFoto'] == null ? const Icon(Icons.person, size: 16) : null),
              Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                margin: EdgeInsets.only(left: isMe ? 50 : 8, right: isMe ? 8 : 50, top: 4, bottom: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12), topRight: const Radius.circular(12),
                    bottomLeft: Radius.circular(isMe ? 12 : 0), bottomRight: Radius.circular(isMe ? 0 : 12)
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))]
                ),
                child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (!isMe) Text(chat['pengirimNama'] ?? "Jemaat", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                    if (chat['isReply'] == true) _buildReplyUI(chat, isMe),
                    
                    if (chat['tipe'] == 'image') Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        InkWell(onTap: () => _showFullImage(chat['fileUrl']), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: chat['fileUrl'], fit: BoxFit.cover))),
                        if (chat['pesan'] != "[Gambar]") Padding(padding: const EdgeInsets.only(top: 5), child: Text(chat['pesan'], style: const TextStyle(fontSize: 15))),
                    ])
                    else if (chat['tipe'] == 'file') InkWell(
                      onTap: () => _bukaFile(chat['fileUrl'], chat['fileName'] ?? "dokumen"), 
                      child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.insert_drive_file, color: Colors.orange, size: 30), const SizedBox(width: 8), Expanded(child: Text(chat['fileName'] ?? "File", style: const TextStyle(color: Colors.indigo, decoration: TextDecoration.underline)))])
                    )
                    else if (chat['tipe'] == 'audio') _buildAudioUI(chat, docId, isMe)
                    else Text(chat['pesan'] ?? "", style: const TextStyle(color: Colors.black87, fontSize: 15)),
                    
                    const SizedBox(height: 4),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Spacer(),
                      Text(formatTimeCustom(waktu), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      if (isMe) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.done_all, size: 14, color: Colors.blue)),
                    ])
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReplyUI(Map<String, dynamic> chat, bool isMe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: isMe ? Colors.green : Colors.indigo, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chat['replyToName'] ?? "Jemaat", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isMe ? Colors.green[800] : Colors.indigo)),
                const SizedBox(height: 2),
                Text(chat['replyToText'] ?? "", maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
          ),
          if (chat['replyToImage'] != null)
            Padding(padding: const EdgeInsets.only(left: 8), child: ClipRRect(borderRadius: BorderRadius.circular(4), child: CachedNetworkImage(imageUrl: chat['replyToImage'], width: 40, height: 40, fit: BoxFit.cover))),
        ],
      ),
    );
  }

  Widget _buildAudioUI(Map<String, dynamic> chat, String id, bool isMe) {
    bool isPlaying = _playingId == id;
    return Row( mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle, color: const Color(0xFF075E54), size: 35), onPressed: () => _playAudio(chat['fileUrl'], id)),
        const Text("Voice Note", style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.black54)),
      ],
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.transparent,
      child: Column( children: [
          if (_replyMessage != null || _editingMessageId != null) Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Row( children: [
                Icon(_editingMessageId != null ? Icons.edit : Icons.reply, color: const Color(0xFF075E54)),
                const SizedBox(width: 10),
                Expanded(child: Text(_editingMessageId != null ? "Edit Pesan..." : (_replyMessage?['pesan'] ?? ""), maxLines: 1, overflow: TextOverflow.ellipsis)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _replyMessage = null; _editingMessageId = null; _etPesan.clear(); }))
              ],
            ),
          ),
          Row( children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
                  child: Row( children: [
                      IconButton(icon: const Icon(Icons.add, color: Colors.grey), onPressed: _showPickerOptions),
                      Expanded(child: TextField(controller: _etPesan, maxLines: null, decoration: const InputDecoration(hintText: "Ketik pesan...", border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 10)))),
                      IconButton(icon: const Icon(Icons.camera_alt, color: Colors.grey), onPressed: _uploadImage),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 5),
              GestureDetector(
                onLongPressStart: (_) => _startRecording(),
                onLongPressEnd: (_) => _stopRecording(),
                child: CircleAvatar(
                  radius: 24, backgroundColor: const Color(0xFF075E54),
                  child: IconButton(
                    icon: Icon(_isTyping ? Icons.send : Icons.mic, color: Colors.white),
                    onPressed: () { if (_isTyping) _sendToFirestore(isi: _etPesan.text.trim(), tipe: "text"); },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}