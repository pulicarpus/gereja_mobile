import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  
  late String _collectionPath;
  bool _isTyping = false;

  // Telegram / OneSignal Config (Sesuai punya Bos)
  final String teleBotToken = "8632837608:AAHzQBShTgNd31OEDLScM-tTQ3i6ImR4XbE";
  final String teleChatId = "-1003815632729";
  final String osAppId = "a9ff250a-56ef-413d-b825-67288008d614";
  final String osRestKey = "os_v2_app_vh7skcsw55at3obfm4uiacgwctohxklw72zurcurxm772cihckdcslgztwftp65s3s4uuv7ivlutx4sphyiwga23t3gkjex5q74kq2y";

  @override
  void initState() {
    super.initState();
    _collectionPath = widget.filterKategorial == null 
        ? "chats" 
        : "chats_${widget.filterKategorial}";
    
    // Deteksi kalau user ngetik biar icon berubah
    _etPesan.addListener(() {
      setState(() {
        _isTyping = _etPesan.text.trim().isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _etPesan.dispose();
    super.dispose();
  }

  // ==== FITUR KIRIM PESAN TEXT ====
  Future<void> _sendMessage(String pesan) async {
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) return;

    _etPesan.clear();

    await _db.collection("churches").doc(churchId).collection(_collectionPath).add({
      "pengirimId": _auth.currentUser?.uid,
      "pengirimNama": UserManager().userNama,
      "pengirimFoto": UserManager().userFotoUrl,
      "pesan": pesan,
      "timestamp": FieldValue.serverTimestamp(),
      "tipe": "text",
      "fileUrl": null,
      "isReply": false, 
    });

    _kirimNotifikasi(pesan);
  }

  // ==== NOTIFIKASI ONESIGNAL (REST API) ====
  Future<void> _kirimNotifikasi(String pesan) async {
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) return;

    String nama = UserManager().userNama ?? "Jemaat";
    String label = widget.filterKategorial != null ? "[${widget.filterKategorial}] " : "";

    try {
      await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic $osRestKey',
        },
        body: jsonEncode({
          "app_id": osAppId,
          "filters": [
            {"field": "tag", "key": "active_church", "relation": "=", "value": churchId},
            {"operator": "AND"},
            {"field": "tag", "key": "kategori_aktif", "relation": "=", "value": widget.filterKategorial?.replaceAll(" ", "_") ?? "Umum"}
          ],
          "headings": {"en": "Chat $nama"},
          "contents": {"en": "$label$pesan"}
        }),
      );
    } catch (e) {
      debugPrint("Gagal kirim notif: $e");
    }
  }

  // ==== ADMIN: HAPUS SEMUA CHAT ====
  Future<void> _hapusSemuaChat() async {
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) return;

    var snapshots = await _db.collection("churches").doc(churchId).collection(_collectionPath).get();
    WriteBatch batch = _db.batch();
    for (var doc in snapshots.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Chat bersih!")));
  }

  @override
  Widget build(BuildContext context) {
    bool isAdmin = UserManager().isAdmin();
    String? churchId = UserManager().activeChurchId;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.filterKategorial == null ? "Ruang Chat Jemaat" : "Chat ${widget.filterKategorial}"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          if (isAdmin)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'clear') _hapusSemuaChat();
                if (value == 'unmute') {
                  // TODO: Panggil fungsi dialog unmute
                }
              },
              itemBuilder: (BuildContext context) => [
                const PopupMenuItem(value: 'unmute', child: Text('Kelola Unmute User')),
                const PopupMenuItem(value: 'clear', child: Text('Hapus Semua Chat', style: TextStyle(color: Colors.red))),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // ==== AREA LIST CHAT (REALTIME) ====
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection("churches").doc(churchId).collection(_collectionPath)
                         .orderBy("timestamp", descending: true) // Flutter butuh descending untuk chat list dari bawah
                         .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                var docs = snapshot.data!.docs;
                if (docs.isEmpty) return const Center(child: Text("Belum ada pesan. Sapa jemaat lain!"));

                return ListView.builder(
                  reverse: true, // Biar chat baru ada di bawah (seperti WA)
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var chat = docs[index].data() as Map<String, dynamic>;
                    bool isMe = chat['pengirimId'] == _auth.currentUser?.uid;

                    // UI Bubble Chat Sederhana
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.indigo[100] : Colors.grey[200],
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMe) Text(chat['pengirimNama'] ?? "Jemaat", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            Text(chat['pesan'] ?? ""),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // ==== AREA BAWAH (INPUT TEXT & TOMBOL) ====
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.blueGrey),
                  onPressed: () {
                    // TODO: Panggil fungsi Image Picker / File Picker
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fitur lampiran segera hadir!")));
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _etPesan,
                    decoration: InputDecoration(
                      hintText: "Ketik pesan...",
                      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.indigo[900],
                  child: IconButton(
                    icon: Icon(_isTyping ? Icons.send : Icons.mic, color: Colors.white),
                    onPressed: () {
                      if (_isTyping) {
                        _sendMessage(_etPesan.text.trim());
                      } else {
                        // TODO: Jalankan fitur Voice Note
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fitur mic segera hadir!")));
                      }
                    },
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