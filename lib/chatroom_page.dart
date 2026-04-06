import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:audio_waveforms/audio_waveforms.dart';
import 'dart:convert';
import 'dart:io';

import 'secrets.dart'; 
import 'user_manager.dart';
import 'recorder_visualizer.dart';
import 'chat_waveform.dart';

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
  late final RecorderController _recorderController; 
  
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
    _recorderController = RecorderController(); 
    _collectionPath = widget.filterKategorial == null ? "chats" : "chats_${widget.filterKategorial}";
    _etPesan.addListener(() => setState(() => _isTyping = _etPesan.text.trim().isNotEmpty));
    _audioPlayer.onPlayerComplete.listen((event) { if (mounted) setState(() => _playingId = null); });
  }

  @override
  void dispose() {
    _etPesan.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _recorderController.dispose();
    super.dispose();
  }

  String formatTimeCustom(DateTime? date) => date == null ? "" : DateFormat('HH:mm').format(date);

  Future<void> _uploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 60);
    if (image == null) return;
    final TextEditingController _etCaption = TextEditingController();
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text("Kirim Gambar"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(File(image.path), height: 150, fit: BoxFit.cover)),
        TextField(controller: _etCaption, decoration: const InputDecoration(hintText: "Keterangan...")),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
        ElevatedButton(onPressed: () { String cap = _etCaption.text; Navigator.pop(context); _executeImageUpload(image, cap.isEmpty ? "[Gambar]" : cap); }, child: const Text("Kirim")),
      ],
    ));
  }

  Future<void> _executeImageUpload(XFile image, String caption) async {
    setState(() => _isUploading = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse('https://api.cloudinary.com/v1_1/dw1ynjbod/image/upload'));
      request.fields['upload_preset'] = 'preset_gereja'; 
      request.files.add(await http.MultipartFile.fromPath('file', image.path));
      var res = await request.send();
      var json = jsonDecode(await res.stream.bytesToString());
      if (res.statusCode == 200) _sendToFirestore(isi: caption, tipe: "image", url: json['secure_url']);
    } catch (e) { _showSnack("Gagal: $e"); } finally { setState(() => _isUploading = false); }
  }

  Future<void> _uploadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null) return;
    setState(() => _isUploading = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse('https://api.telegram.org/bot$teleBotToken/sendDocument'));
      request.fields['chat_id'] = teleChatId;
      request.files.add(await http.MultipartFile.fromPath('document', result.files.single.path!));
      var res = await request.send();
      if (res.statusCode == 200) {
        var jsonRes = jsonDecode(await res.stream.bytesToString());
        String fileId = jsonRes['result']['document']['file_id'];
        var getFile = await http.get(Uri.parse('https://api.telegram.org/bot$teleBotToken/getFile?file_id=$fileId'));
        String path = jsonDecode(getFile.body)['result']['file_path'];
        _sendToFirestore(isi: result.files.single.name, tipe: "file", url: "https://api.telegram.org/file/bot$teleBotToken/$path", name: result.files.single.name);
      }
    } catch (e) { _showSnack("Gagal: $e"); } finally { setState(() => _isUploading = false); }
  }

  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      HapticFeedback.heavyImpact(); 
      await _recorderController.record(); 
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/vn_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(const RecordConfig(), path: path); 
      setState(() => _isRecording = true);
    }
  }

  Future<void> _stopRecording() async {
    HapticFeedback.mediumImpact(); 
    final rawWaveData = List<double>.from(_recorderController.waveformData);
    List<double> compressedData = [];
    if (rawWaveData.isNotEmpty) {
      int step = (rawWaveData.length / 30).floor().clamp(1, 999);
      for (int i = 0; i < rawWaveData.length; i += step) {
        compressedData.add(rawWaveData[i]);
        if (compressedData.length >= 30) break;
      }
    }
    final path = await _audioRecorder.stop();
    await _recorderController.stop(); 
    setState(() => _isRecording = false);
    if (path != null) _uploadVN(File(path), compressedData);
  }

  Future<void> _uploadVN(File file, List<double> waveData) async {
    setState(() => _isUploading = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse('https://api.telegram.org/bot$teleBotToken/sendAudio'));
      request.fields['chat_id'] = teleChatId;
      request.files.add(await http.MultipartFile.fromPath('audio', file.path));
      var res = await request.send();
      if (res.statusCode == 200) {
        var jsonRes = jsonDecode(await res.stream.bytesToString());
        String fileId = jsonRes['result']['audio']['file_id'];
        var getFile = await http.get(Uri.parse('https://api.telegram.org/bot$teleBotToken/getFile?file_id=$fileId'));
        String path = jsonDecode(getFile.body)['result']['file_path'];
        _sendToFirestore(isi: "[Voice Note]", tipe: "audio", url: "https://api.telegram.org/file/bot$teleBotToken/$path", waveData: waveData);
      }
    } catch (e) { _showSnack("Gagal: $e"); } finally { setState(() => _isUploading = false); }
  }

  Future<void> _playAudio(String url, String id) async {
    if (_playingId == id) { await _audioPlayer.pause(); setState(() => _playingId = null); }
    else { await _audioPlayer.play(UrlSource(url)); setState(() => _playingId = id); }
  }

  Future<void> _sendToFirestore({required String isi, required String tipe, String? url, String? name, List<double>? waveData}) async {
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) return;
    if (_editingMessageId != null) {
      await _db.collection("churches").doc(churchId).collection(_collectionPath).doc(_editingMessageId).update({"pesan": "$isi (diedit)"});
      setState(() { _editingMessageId = null; _etPesan.clear(); });
      return;
    }
    await _db.collection("churches").doc(churchId).collection(_collectionPath).add({
      "pengirimId": _auth.currentUser?.uid, "pengirimNama": UserManager().userNama, "pengirimFoto": UserManager().userFotoUrl,
      "pesan": isi, "timestamp": FieldValue.serverTimestamp(), "tipe": tipe, "fileUrl": url, "fileName": name, "waveData": waveData,
      "isReply": _replyMessage != null, "replyToName": _replyMessage?['pengirimNama'], "replyToText": _replyMessage?['pesan'],
      "replyToImage": (_replyMessage != null && _replyMessage!['tipe'] == 'image') ? _replyMessage!['fileUrl'] : null,
    });
    _kirimNotif(isi);
    setState(() { _replyMessage = null; _etPesan.clear(); });
  }

  Future<void> _kirimNotif(String pesan) async {
    String? churchId = UserManager().activeChurchId;
    if (churchId == null || osRestKey.isEmpty) return;
    try {
      await http.post(Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Basic $osRestKey'},
        body: jsonEncode({
          "app_id": osAppId,
          "filters": [{"field": "tag", "key": "active_church", "relation": "=", "value": churchId}],
          "headings": {"en": "Chat: ${UserManager().userNama}"}, "contents": {"en": pesan}
        }),
      );
    } catch (_) {}
  }

  void _showChatMenu(Map<String, dynamic> chat, String docId) {
    bool isMe = chat['pengirimId'] == _auth.currentUser?.uid;
    showModalBottomSheet(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.reply), title: const Text("Balas"), onTap: () { Navigator.pop(context); setState(() { _replyMessage = chat; _editingMessageId = null; }); }),
      if (isMe && chat['tipe'] == 'text') ListTile(leading: const Icon(Icons.edit), title: const Text("Edit"), onTap: () { Navigator.pop(context); setState(() { _editingMessageId = docId; _etPesan.text = chat['pesan'].replaceAll(" (diedit)", ""); }); }),
      if (isMe || UserManager().isAdmin()) ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("Hapus"), onTap: () { Navigator.pop(context); _db.collection("churches").doc(UserManager().activeChurchId).collection(_collectionPath).doc(docId).delete(); }),
    ])));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5DDD5),
      appBar: AppBar(title: const Text("Chat Jemaat"), backgroundColor: const Color(0xFF075E54), foregroundColor: Colors.white),
      body: Column(children: [
        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: _db.collection("churches").doc(UserManager().activeChurchId).collection(_collectionPath).orderBy("timestamp", descending: true).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            var docs = snap.data!.docs;
            return ListView.builder(reverse: true, padding: const EdgeInsets.all(10), itemCount: docs.length, itemBuilder: (context, i) {
              var chat = docs[i].data() as Map<String, dynamic>;
              return _buildChatBubble(chat, docs[i].id, chat['pengirimId'] == _auth.currentUser?.uid);
            });
          },
        )),
        _buildInputArea(),
      ]),
    );
  }

  Widget _buildChatBubble(Map<String, dynamic> chat, String docId, bool isMe) {
    DateTime? waktu = (chat['timestamp'] as Timestamp?)?.toDate();
    return GestureDetector(
      onLongPress: () => _showChatMenu(chat, docId),
      child: Row(mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!isMe) CircleAvatar(radius: 16, backgroundImage: chat['pengirimFoto'] != null ? CachedNetworkImageProvider(chat['pengirimFoto']) : null),
        Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: isMe ? const Color(0xFFDCF8C6) : Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!isMe) Text(chat['pengirimNama'] ?? "Jemaat", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
            if (chat['isReply'] == true) _buildReplyUI(chat, isMe),
            if (chat['tipe'] == 'audio') _buildAudioUI(chat, docId, isMe)
            else Text(chat['pesan'] ?? "", style: const TextStyle(fontSize: 15)),
            Row(mainAxisSize: MainAxisSize.min, children: [const Spacer(), Text(formatTimeCustom(waktu), style: const TextStyle(fontSize: 10, color: Colors.grey))])
          ]),
        ),
      ]),
    );
  }

  Widget _buildReplyUI(Map<String, dynamic> chat, bool isMe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.06), borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: isMe ? Colors.green[800]! : Colors.indigo, width: 4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(chat['replyToName'] ?? "", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isMe ? Colors.green[800] : Colors.indigo)),
        Text(chat['replyToText'] ?? "", style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ]),
    );
  }

  Widget _buildAudioUI(Map<String, dynamic> chat, String id, bool isMe) {
    bool isPlaying = _playingId == id;
    List<double> samples = chat['waveData'] != null ? List<double>.from(chat['waveData'].map((e) => e.toDouble())) : [];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle, color: const Color(0xFF075E54), size: 35), onPressed: () => _playAudio(chat['fileUrl'], id)),
      if (samples.isNotEmpty) ChatWaveform(samples: samples, isMe: isMe) else const Text("Voice Note", style: TextStyle(fontStyle: FontStyle.italic))
    ]);
  }

  Widget _buildInputArea() {
    return Container(padding: const EdgeInsets.all(8), child: Column(children: [
      if (_isRecording) Padding(padding: const EdgeInsets.only(bottom: 12), child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.mic, color: Colors.red), const SizedBox(width: 10), RecorderVisualizer(controller: _recorderController), const Text("Recording", style: TextStyle(color: Colors.red))]))),
      Row(children: [
        Expanded(child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)), child: Row(children: [IconButton(icon: const Icon(Icons.add), onPressed: () => _uploadFile()), Expanded(child: TextField(controller: _etPesan, decoration: const InputDecoration(hintText: "Ketik pesan...", border: InputBorder.none))), IconButton(icon: const Icon(Icons.camera_alt), onPressed: _uploadImage)]))),
        const SizedBox(width: 5),
        GestureDetector(onLongPressStart: (_) => _startRecording(), onLongPressEnd: (_) => _stopRecording(), child: CircleAvatar(backgroundColor: const Color(0xFF075E54), child: IconButton(icon: Icon(_isTyping ? Icons.send : Icons.mic, color: Colors.white), onPressed: () { if (_isTyping) _sendToFirestore(isi: _etPesan.text.trim(), tipe: "text"); })))
      ])
    ]));
  }

  void _showSnack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
}