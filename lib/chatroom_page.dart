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
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'secrets.dart'; 
import 'user_manager.dart';
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
  
  // Audio direkam hanya oleh package record agar mikrofon tidak dibuka
  // oleh dua recorder sekaligus.
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  final List<double> _recordingSamples = [];
  
  bool _isRecording = false;
  String? _playingId;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  late String _collectionPath;
  bool _isTyping = false;
  bool _isUploading = false;
  bool _isSending = false;
  int _messageLimit = 100;
  DateTime? _lastSendAt;

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
    
    _etPesan.addListener(() {
      if (mounted) {
        setState(() => _isTyping = _etPesan.text.trim().isNotEmpty);
      }
    });
    
    _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _currentPosition = pos);
    });
    _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _totalDuration = dur);
    });
    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) setState(() { _playingId = null; _currentPosition = Duration.zero; });
    });
  }

  @override
  void dispose() {
    _etPesan.dispose();
    _amplitudeSubscription?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  String? get _churchId {
    final id = UserManager().getChurchIdForCurrentView();
    return (id == null || id.trim().isEmpty) ? null : id.trim();
  }

  bool get _canAccessRoom {
    final user = UserManager();
    final kategori = widget.filterKategorial?.trim();
    if (kategori == null || kategori.isEmpty) return _auth.currentUser != null;
    return user.isAdmin() || user.userKomisi?.trim() == kategori;
  }

  bool get _canModerate {
    final user = UserManager();
    final kategori = widget.filterKategorial?.trim();
    if (user.isAdmin()) return true;
    return kategori != null &&
        kategori.isNotEmpty &&
        user.isPengurus &&
        user.userKomisi?.trim() == kategori;
  }

  DateTime? _readTimestamp(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  String _safeFileName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll('..', '_')
        .trim();
    return cleaned.isEmpty ? 'dokumen' : cleaned;
  }

  String formatTimeCustom(DateTime? date) {
    if (date == null) return "";
    return DateFormat('HH:mm').format(date);
  }

  Future<bool> _checkIfMuted() async {
    final churchId = _churchId;
    final uid = _auth.currentUser?.uid;
    if (churchId == null || uid == null || uid.isEmpty) {
      _showSnack("Sesi chat tidak valid. Silakan buka ulang halaman.");
      return true;
    }

    try {
      final muteDoc = await _db
          .collection("churches")
          .doc(churchId)
          .collection("muted_$_collectionPath")
          .doc(uid)
          .get();

      if (muteDoc.exists) {
        if (mounted) {
          await showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: const Row(
                children: [
                  Icon(Icons.gavel, color: Colors.red),
                  SizedBox(width: 8),
                  Text("Akses Dibatasi"),
                ],
              ),
              content: const Text(
                "Anda sedang di-Mute oleh Pengurus. Pesan tetap bisa dibaca, tetapi pengiriman pesan dan lampiran dinonaktifkan.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Mengerti"),
                ),
              ],
            ),
          );
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Gagal memeriksa status mute: $e");
      _showSnack("Status chat tidak dapat diverifikasi. Coba lagi.");
      return true;
    }
  }

  // --- 1. UPLOAD GAMBAR DENGAN CAPTION DIALOG ---
  Future<void> _uploadImage() async {
    if (_isUploading || _isSending || _editingMessageId != null) {
      if (_editingMessageId != null) {
        _showSnack("Selesaikan atau batalkan edit pesan sebelum mengirim lampiran.");
      }
      return;
    }
    if (await _checkIfMuted()) return;

    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 60,
      maxWidth: 1800,
    );
    if (image == null || !mounted) return;

    final captionController = TextEditingController();
    final caption = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          "Kirim Gambar",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(image.path),
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: captionController,
              maxLength: 500,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: "Tambah keterangan...",
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Batal", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF075E54),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(
              dialogContext,
              captionController.text.trim(),
            ),
            child: const Text("Kirim"),
          ),
        ],
      ),
    );
    captionController.dispose();

    if (caption == null) return;
    await _executeImageUpload(
      image,
      caption.isEmpty ? "[Gambar]" : caption,
    );
  }

  Future<void> _executeImageUpload(XFile image, String caption) async {
    if (_isUploading || await _checkIfMuted()) return;
    if (mounted) setState(() => _isUploading = true);
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.cloudinary.com/v1_1/dw1ynjbod/image/upload'),
      );
      request.fields['upload_preset'] = 'preset_gereja';
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      final res = await request.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _showSnack("Upload gambar gagal. Coba lagi.");
        return;
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map ||
          decoded['secure_url'] == null ||
          decoded['public_id'] == null) {
        _showSnack("Respons upload gambar tidak valid.");
        return;
      }

      await _sendToFirestore(
        isi: caption,
        tipe: "image",
        url: decoded['secure_url'].toString(),
        name: "img.jpg",
        cloudId: decoded['public_id'].toString(),
      );
    } catch (e) {
      debugPrint("Gagal upload gambar: $e");
      _showSnack("Gagal upload gambar.");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // --- 2. UPLOAD FILE DOKUMEN ---
  Future<void> _uploadFile() async {
    if (_isUploading || _isSending || _editingMessageId != null) {
      if (_editingMessageId != null) {
        _showSnack("Selesaikan atau batalkan edit pesan sebelum mengirim lampiran.");
      }
      return;
    }
    if (await _checkIfMuted()) return;

    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final path = picked.path;
    if (path == null || path.isEmpty) {
      _showSnack("File tidak dapat diakses.");
      return;
    }
    const maxFileSize = 20 * 1024 * 1024;
    if (picked.size > maxFileSize) {
      _showSnack("Ukuran dokumen maksimal 20 MB.");
      return;
    }

    final file = File(path);
    final fileName = _safeFileName(picked.name);
    if (mounted) setState(() => _isUploading = true);

    try {
      if (teleBotToken.isEmpty) {
        _showSnack("Layanan dokumen sedang tidak tersedia.");
        return;
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.telegram.org/bot$teleBotToken/sendDocument'),
      );
      request.fields['chat_id'] = teleChatId;
      request.files.add(
        await http.MultipartFile.fromPath('document', file.path),
      );

      final res = await request.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _showSnack("Upload dokumen gagal.");
        return;
      }

      final jsonRes = jsonDecode(body);
      final fileId = jsonRes is Map
          ? jsonRes['result']?['document']?['file_id']?.toString()
          : null;
      if (fileId == null || fileId.isEmpty) {
        _showSnack("Respons upload dokumen tidak valid.");
        return;
      }

      final getFile = await http.get(
        Uri.parse(
          'https://api.telegram.org/bot$teleBotToken/getFile?file_id=$fileId',
        ),
      );
      if (getFile.statusCode < 200 || getFile.statusCode >= 300) {
        _showSnack("Dokumen terunggah tetapi tautannya gagal dibuat.");
        return;
      }

      final getFileJson = jsonDecode(getFile.body);
      final filePath = getFileJson is Map
          ? getFileJson['result']?['file_path']?.toString()
          : null;
      if (filePath == null || filePath.isEmpty) {
        _showSnack("Tautan dokumen tidak tersedia.");
        return;
      }

      await _sendToFirestore(
        isi: fileName,
        tipe: "file",
        url: "https://api.telegram.org/file/bot$teleBotToken/$filePath",
        name: fileName,
      );
    } catch (e) {
      debugPrint("Gagal kirim file: $e");
      _showSnack("Gagal mengirim dokumen.");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // --- 3. VOICE NOTE ---
  Future<void> _startRecording() async {
    if (_isRecording || _isUploading || _isSending || _editingMessageId != null) {
      return;
    }
    if (await _checkIfMuted()) return;

    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _showSnack("Izin mikrofon diperlukan untuk mengirim voice note.");
        return;
      }

      HapticFeedback.heavyImpact();
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/vn_${DateTime.now().millisecondsSinceEpoch}.m4a';

      _recordingSamples.clear();
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((amp) {
        // Nilai dB biasanya negatif. Normalisasi -60..0 menjadi 0..1.
        final normalized = ((amp.current + 60) / 60).clamp(0.05, 1.0);
        _recordingSamples.add(normalized.toDouble());
        if (_recordingSamples.length > 600) {
          _recordingSamples.removeAt(0);
        }
      });

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      debugPrint("Gagal merekam: $e");
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      if (mounted) setState(() => _isRecording = false);
      _showSnack("Gagal memulai rekaman.");
    }
  }

  List<double> _compressWaveData(List<double> raw) {
    if (raw.isEmpty) return const [];
    final result = <double>[];
    final step = (raw.length / 30).ceil().clamp(1, raw.length);
    for (var i = 0; i < raw.length && result.length < 30; i += step) {
      result.add(raw[i]);
    }
    return result;
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    HapticFeedback.mediumImpact();
    String? path;
    try {
      path = await _audioRecorder.stop();
    } catch (e) {
      debugPrint("Gagal menghentikan rekaman: $e");
    } finally {
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      if (mounted) setState(() => _isRecording = false);
    }

    if (path == null || path.isEmpty) {
      _showSnack("Rekaman tidak berhasil disimpan.");
      return;
    }

    final file = File(path);
    if (!await file.exists() || await file.length() == 0) {
      _showSnack("Rekaman kosong.");
      return;
    }

    await _uploadVN(file, _compressWaveData(_recordingSamples));
  }

  Future<void> _uploadVN(File file, List<double> waveData) async {
    if (_isUploading || await _checkIfMuted()) return;
    if (mounted) setState(() => _isUploading = true);

    try {
      if (teleBotToken.isEmpty) {
        _showSnack("Layanan voice note sedang tidak tersedia.");
        return;
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.telegram.org/bot$teleBotToken/sendAudio'),
      );
      request.fields['chat_id'] = teleChatId;
      request.files.add(
        await http.MultipartFile.fromPath('audio', file.path),
      );

      final res = await request.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _showSnack("Upload voice note gagal.");
        return;
      }

      final jsonRes = jsonDecode(body);
      final fileId = jsonRes is Map
          ? (jsonRes['result']?['audio']?['file_id'] ??
                  jsonRes['result']?['voice']?['file_id'])
              ?.toString()
          : null;
      if (fileId == null || fileId.isEmpty) {
        _showSnack("Respons voice note tidak valid.");
        return;
      }

      final getFile = await http.get(
        Uri.parse(
          'https://api.telegram.org/bot$teleBotToken/getFile?file_id=$fileId',
        ),
      );
      if (getFile.statusCode < 200 || getFile.statusCode >= 300) {
        _showSnack("Voice note terunggah tetapi tautannya gagal dibuat.");
        return;
      }

      final fileInfo = jsonDecode(getFile.body);
      final filePath = fileInfo is Map
          ? fileInfo['result']?['file_path']?.toString()
          : null;
      if (filePath == null || filePath.isEmpty) {
        _showSnack("Tautan voice note tidak tersedia.");
        return;
      }

      await _sendToFirestore(
        isi: "[Voice Note]",
        tipe: "audio",
        url: "https://api.telegram.org/file/bot$teleBotToken/$filePath",
        waveData: waveData,
      );
    } catch (e) {
      debugPrint("Gagal kirim VN: $e");
      _showSnack("Gagal mengirim voice note.");
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _playAudio(String url, String id) async {
    if (url.trim().isEmpty) {
      _showSnack("Voice note tidak tersedia.");
      return;
    }
    try {
      if (_playingId != id && _playingId != null) {
        await _audioPlayer.stop();
        if (mounted) {
          setState(() {
            _currentPosition = Duration.zero;
            _totalDuration = Duration.zero;
          });
        }
      }

      if (_playingId == id) {
        await _audioPlayer.pause();
        if (mounted) setState(() => _playingId = null);
      } else {
        await _audioPlayer.play(UrlSource(url));
        if (mounted) {
          setState(() {
            _playingId = id;
            _currentPosition = Duration.zero;
          });
        }
      }
    } catch (e) {
      debugPrint("Gagal memutar audio: $e");
      if (mounted) setState(() => _playingId = null);
      _showSnack("Voice note gagal diputar.");
    }
  }

  // --- 4. FIRESTORE & NOTIFIKASI & EDIT ---
  Future<bool> _sendToFirestore({
    required String isi,
    required String tipe,
    String? url,
    String? name,
    String? cloudId,
    List<double>? waveData,
  }) async {
    if (_isSending) return false;
    if (!_canAccessRoom) {
      _showSnack("Anda tidak memiliki akses ke ruang chat ini.");
      return false;
    }
    if (await _checkIfMuted()) return false;

    final churchId = _churchId;
    final currentUser = _auth.currentUser;
    if (churchId == null || currentUser == null) {
      _showSnack("Sesi chat tidak valid.");
      return false;
    }

    final text = isi.trim();
    if (tipe == "text" && text.isEmpty) return false;
    if (text.length > 2000) {
      _showSnack("Pesan maksimal 2.000 karakter.");
      return false;
    }

    final now = DateTime.now();
    if (_editingMessageId == null &&
        _lastSendAt != null &&
        now.difference(_lastSendAt!) < const Duration(milliseconds: 700)) {
      return false;
    }

    if (mounted) setState(() => _isSending = true);
    try {
      if (_editingMessageId != null) {
        if (tipe != "text") {
          _showSnack("Lampiran tidak dapat dikirim saat sedang mengedit pesan.");
          return false;
        }

        final ref = _db
            .collection("churches")
            .doc(churchId)
            .collection(_collectionPath)
            .doc(_editingMessageId);
        final current = await ref.get();
        if (!current.exists) {
          _showSnack("Pesan yang diedit sudah tidak tersedia.");
          return false;
        }
        final data = current.data() as Map<String, dynamic>;
        final ownerUid =
            (data['pengirimId'] ?? data['senderId'] ?? '').toString();
        if (ownerUid != currentUser.uid ||
            (data['tipe'] ?? 'text').toString() != 'text') {
          _showSnack("Pesan ini tidak dapat diedit.");
          return false;
        }

        await ref.update({"pesan": "$text (diedit)"});
        if (mounted) {
          setState(() {
            _editingMessageId = null;
            _replyMessage = null;
            _etPesan.clear();
          });
        }
        return true;
      }

      final reply = _replyMessage;
      await _db
          .collection("churches")
          .doc(churchId)
          .collection(_collectionPath)
          .add({
        "pengirimId": currentUser.uid,
        "pengirimNama": UserManager().userNama ?? currentUser.displayName ?? "Jemaat",
        "pengirimFoto": UserManager().userFotoUrl,
        "pesan": text,
        "timestamp": FieldValue.serverTimestamp(),
        "tipe": tipe,
        "fileUrl": url,
        "fileName": name,
        "cloudPublicId": cloudId,
        "waveData": waveData,
        "isReply": reply != null,
        "replyToName": reply?['pengirimNama'] ?? reply?['senderNama'],
        "replyToText": reply?['pesan'],
        "replyToImage":
            (reply != null && reply['tipe'] == 'image') ? reply['fileUrl'] : null,
      });

      _lastSendAt = now;
      if (mounted) {
        setState(() {
          _replyMessage = null;
          _etPesan.clear();
        });
      }
      unawaited(_kirimNotif(text));
      return true;
    } catch (e) {
      debugPrint("Gagal menyimpan pesan chat: $e");
      _showSnack("Pesan gagal dikirim. Coba lagi.");
      return false;
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _kirimNotif(String pesan) async {
    final churchId = _churchId;
    if (churchId == null || osRestKey.isEmpty) return;

    final kategori = widget.filterKategorial?.trim();
    final filters = <Map<String, dynamic>>[
      {
        "field": "tag",
        "key": "active_church",
        "relation": "=",
        "value": churchId,
      },
    ];

    if (kategori != null && kategori.isNotEmpty) {
      filters
        ..add({"operator": "AND"})
        ..add({
          "field": "tag",
          "key": "kelompok",
          "relation": "=",
          "value": kategori,
        });
    }

    try {
      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic $osRestKey',
        },
        body: jsonEncode({
          "app_id": osAppId,
          "filters": filters,
          "headings": {"en": "Chat: ${UserManager().userNama ?? 'Jemaat'}"},
          "contents": {
            "en": pesan.isEmpty ? "Pesan baru" : pesan,
          },
          "data": {
            "type": "chat",
            "kategorial": widget.filterKategorial,
          },
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint("Notifikasi chat ditolak: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Gagal mengirim notifikasi chat: $e");
    }
  }

  // --- 5. UI BUILDING ---
  Future<void> _bukaFile(String url, String fileName) async {
    if (url.trim().isEmpty) {
      _showSnack("Dokumen tidak tersedia.");
      return;
    }
    _showSnack("Mengunduh dokumen...");
    try {
      final dir = await getTemporaryDirectory();
      final safeName = _safeFileName(fileName);
      final key = url.hashCode.abs();
      final savePath = '${dir.path}/${key}_$safeName';
      final file = File(savePath);

      if (!await file.exists()) {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          _showSnack("Dokumen gagal diunduh.");
          return;
        }
        const maxDownloadSize = 25 * 1024 * 1024;
        if (response.bodyBytes.length > maxDownloadSize) {
          _showSnack("Dokumen terlalu besar untuk dibuka dari chat.");
          return;
        }
        await file.writeAsBytes(response.bodyBytes, flush: true);
      }

      final result = await OpenFilex.open(savePath);
      if (result.type == ResultType.error) {
        _showSnack("Dokumen sudah diunduh tetapi tidak dapat dibuka.");
      }
    } catch (e) {
      debugPrint("Gagal membuka file: $e");
      _showSnack("Gagal membuka file.");
    }
  }

  Future<void> _deleteMessage(
    String docId,
    String ownerUid,
  ) async {
    final currentUid = _auth.currentUser?.uid ?? "";
    if (currentUid.isEmpty || (ownerUid != currentUid && !_canModerate)) {
      _showSnack("Anda tidak memiliki izin untuk menghapus pesan ini.");
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Hapus Pesan"),
        content: const Text(
          "Pesan akan dihapus dari ruang chat. Lampiran eksternal yang pernah diunggah mungkin tetap tersimpan sampai backend dibersihkan.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Hapus"),
          ),
        ],
      ),
    ) ?? false;
    if (!confirmed) return;

    final churchId = _churchId;
    if (churchId == null) return;

    try {
      final ref = _db
          .collection("churches")
          .doc(churchId)
          .collection(_collectionPath)
          .doc(docId);
      final latest = await ref.get();
      if (!latest.exists) {
        _showSnack("Pesan sudah tidak tersedia.");
        return;
      }
      final data = latest.data() as Map<String, dynamic>;
      final latestOwner =
          (data['pengirimId'] ?? data['senderId'] ?? '').toString();
      if (latestOwner != currentUid && !_canModerate) {
        _showSnack("Izin menghapus pesan berubah.");
        return;
      }
      await ref.delete();
      _showSnack("Pesan dihapus.");
    } catch (e) {
      debugPrint("Gagal menghapus pesan: $e");
      _showSnack("Gagal menghapus pesan.");
    }
  }

  void _showChatMenu(Map<String, dynamic> chat, String docId) {
    final uidPesan =
        (chat['pengirimId'] ?? chat['senderId'] ?? "").toString();
    final isMe = uidPesan == _auth.currentUser?.uid;
    final tipe = (chat['tipe'] ?? 'text').toString();
    final pesan = (chat['pesan'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text("Balas"),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() {
                  _replyMessage = Map<String, dynamic>.from(chat);
                  _editingMessageId = null;
                  _etPesan.clear();
                });
              },
            ),
            if (isMe && tipe == 'text')
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text("Edit Pesan"),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() {
                    _editingMessageId = docId;
                    _replyMessage = null;
                    _etPesan.text =
                        pesan.replaceFirst(RegExp(r' \(diedit\)$'), "");
                  });
                },
              ),
            if (isMe || _canModerate)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  "Hapus",
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteMessage(docId, uidPesan);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showModerationMenu(
    String targetUid,
    String targetName,
  ) async {
    if (!_canModerate ||
        targetUid == _auth.currentUser?.uid ||
        targetUid.isEmpty) {
      return;
    }

    final churchId = _churchId;
    if (churchId == null) return;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final ref = _db
          .collection("churches")
          .doc(churchId)
          .collection("muted_$_collectionPath")
          .doc(targetUid);
      final doc = await ref.get();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final isMuted = doc.exists;
      await showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "Moderasi: $targetName",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  isMuted ? Icons.volume_up : Icons.volume_off,
                  color: isMuted ? Colors.green : Colors.red,
                ),
                title: Text(
                  isMuted
                      ? "Unmute (Buka Suara)"
                      : "Mute (Bungkam)",
                ),
                subtitle: Text(
                  isMuted
                      ? "Izinkan $targetName mengirim pesan lagi."
                      : "Cegah $targetName mengirim pesan di grup ini.",
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  if (!_canModerate) {
                    _showSnack("Izin moderasi sudah berubah.");
                    return;
                  }
                  try {
                    if (isMuted) {
                      await ref.delete();
                      _showSnack("$targetName berhasil di-unmute.");
                    } else {
                      await ref.set({
                        "muted": true,
                        "timestamp": FieldValue.serverTimestamp(),
                      });
                      _showSnack("$targetName berhasil dibungkam (mute).");
                    }
                  } catch (e) {
                    debugPrint("Gagal mengubah mute: $e");
                    _showSnack("Gagal mengubah status mute.");
                  }
                },
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint("Gagal memuat status moderasi: $e");
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        _showSnack("Gagal memuat status moderasi.");
      }
    }
  }

  void _showFullImage(String url) {
    if (url.trim().isEmpty) {
      _showSnack("Gambar tidak tersedia.");
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, __) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (_, __, ___) => const Center(
                  child: Text(
                    "Gambar tidak dapat dimuat.",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPickerOptions() {
    if (_isUploading || _isSending || _editingMessageId != null) {
      if (_editingMessageId != null) {
        _showSnack("Selesaikan atau batalkan edit pesan terlebih dahulu.");
      }
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image, color: Colors.blue),
              title: const Text("Kirim Gambar"),
              onTap: () {
                Navigator.pop(sheetContext);
                _uploadImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_present, color: Colors.orange),
              title: const Text("Kirim Dokumen"),
              subtitle: const Text("Maksimal 20 MB"),
              onTap: () {
                Navigator.pop(sheetContext);
                _uploadFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.filterKategorial != null ? "Chat ${widget.filterKategorial}" : "Chat Jemaat";
    return Scaffold(
      backgroundColor: const Color(0xFFE5DDD5),
      appBar: AppBar(title: Text(title), backgroundColor: const Color(0xFF075E54), foregroundColor: Colors.white, actions: [if (_isUploading) const Padding(padding: EdgeInsets.all(15), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))]),
      body: Column(children: [
        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: _db.collection("churches").doc(UserManager().activeChurchId).collection(_collectionPath).orderBy("timestamp", descending: true).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            var docs = snap.data!.docs;
            return ListView.builder(reverse: true, padding: const EdgeInsets.all(10), itemCount: docs.length, itemBuilder: (context, i) {
              var chat = docs[i].data() as Map<String, dynamic>;
              return _buildChatBubble(chat, docs[i].id);
            });
          },
        )),
        _buildInputArea(),
      ]),
    );
  }

  // 👇 RENDER KARTU LAMPIRAN SULTAN UNTUK INFO DAERAH 👇
  Widget _buildInfoDaerahUI(Map<String, dynamic> chat) {
    String pesan = chat['pesan'] ?? "";
    String? url = chat['lampiranUrl'] ?? chat['fileUrl'];
    bool isImage = chat['isImage'] == true || chat['tipe'] == 'image';
    String fileName = chat['namaFile'] ?? chat['fileName'] ?? "Dokumen Edaran Daerah";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(pesan, style: const TextStyle(color: Colors.black87, fontSize: 15)),
        if (url != null && url.isNotEmpty) ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: () {
              if (isImage) {
                _showFullImage(url);
              } else {
                _bukaFile(url, fileName);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade200),
                borderRadius: BorderRadius.circular(8)
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isImage ? Icons.image : Icons.picture_as_pdf, color: Colors.red.shade700, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isImage ? "Lihat Gambar Edaran" : "Buka Dokumen Edaran",
                      style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    )
                  )
                ]
              )
            )
          )
        ]
      ]
    );
  }

  Widget _buildChatBubble(Map<String, dynamic> chat, String docId) {
    DateTime? waktu = (chat['timestamp'] as Timestamp?)?.toDate();
    
    // PENYESUAIAN PINTAR KARENA PERBEDAAN LABEL DAERAH & LOKAL
    bool isInfoDaerah = chat['isInfoDaerah'] == true;
    String uidPesan = chat['pengirimId'] ?? chat['senderId'] ?? "";
    bool isMe = uidPesan == _auth.currentUser?.uid;
    String pengirimNama = chat['pengirimNama'] ?? chat['senderNama'] ?? "Jemaat";
    
    return GestureDetector(
      onLongPress: () => _showChatMenu(chat, docId),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, 
        children: [
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start, 
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              if (!isMe) 
                GestureDetector(
                  onTap: () => _showModerationMenu(uidPesan, pengirimNama),
                  child: CircleAvatar(
                    radius: 16, 
                    backgroundImage: chat['pengirimFoto'] != null ? CachedNetworkImageProvider(chat['pengirimFoto']) : null, 
                    child: chat['pengirimFoto'] == null ? const Icon(Icons.person, size: 16) : null
                  ),
                ),
              
              Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                margin: EdgeInsets.only(left: isMe ? 50 : 8, right: isMe ? 8 : 50, top: 4, bottom: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isInfoDaerah ? Colors.white : (isMe ? const Color(0xFFDCF8C6) : Colors.white), 
                  borderRadius: BorderRadius.only(topLeft: const Radius.circular(12), topRight: const Radius.circular(12), bottomLeft: Radius.circular(isMe ? 12 : 0), bottomRight: Radius.circular(isMe ? 0 : 12)), 
                  border: isInfoDaerah ? Border.all(color: Colors.red.shade300, width: 1.5) : null,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))]
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    if (!isMe) Text(
                      pengirimNama, 
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 12, 
                        color: isInfoDaerah ? Colors.red.shade700 : Colors.blueGrey
                      )
                    ),
                    if (chat['isReply'] == true) _buildReplyUI(chat, isMe),
                    
                    // RENDER INFO DAERAH KHUSUS
                    if (isInfoDaerah)
                      _buildInfoDaerahUI(chat)
                    // RENDER GAMBAR
                    else if (chat['tipe'] == 'image') 
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start, 
                        children: [
                          InkWell(onTap: () => _showFullImage(chat['fileUrl']), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: chat['fileUrl'], fit: BoxFit.cover))),
                          if (chat['pesan'] != "[Gambar]") Padding(padding: const EdgeInsets.only(top: 5), child: Text(chat['pesan'], style: const TextStyle(fontSize: 15))),
                        ]
                      )
                    // RENDER FILE
                    else if (chat['tipe'] == 'file') 
                      InkWell(
                        onTap: () => _bukaFile(chat['fileUrl'], chat['fileName'] ?? "dokumen"), 
                        child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.insert_drive_file, color: Colors.orange, size: 30), const SizedBox(width: 8), Expanded(child: Text(chat['fileName'] ?? "File", style: const TextStyle(color: Colors.indigo, decoration: TextDecoration.underline)))])
                      )
                    // RENDER AUDIO
                    else if (chat['tipe'] == 'audio') 
                      _buildAudioUI(chat, docId, isMe)
                    // RENDER TEXT BIASA
                    else 
                      Text(chat['pesan'] ?? "", style: const TextStyle(color: Colors.black87, fontSize: 15)),
                    
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min, 
                      children: [
                        const Spacer(), 
                        Text(formatTimeCustom(waktu), style: const TextStyle(fontSize: 10, color: Colors.grey)), 
                        if (isMe) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.done_all, size: 14, color: Colors.blue))
                      ]
                    )
                  ]
                ),
              ),
            ]
          ),
        ]
      ),
    );
  }

  Widget _buildReplyUI(Map<String, dynamic> chat, bool isMe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.06), borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: isMe ? Colors.green[800]! : Colors.indigo, width: 4))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                Text(chat['replyToName'] ?? "Jemaat", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isMe ? Colors.green[800] : Colors.indigo)),
                const SizedBox(height: 2),
                Text(chat['replyToText'] ?? "", style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.3)),
              ]
            )
          ),
          if (chat['replyToImage'] != null) Padding(padding: const EdgeInsets.only(left: 8), child: ClipRRect(borderRadius: BorderRadius.circular(4), child: CachedNetworkImage(imageUrl: chat['replyToImage'], width: 45, height: 45, fit: BoxFit.cover))),
        ]
      ),
    );
  }

  Widget _buildAudioUI(Map<String, dynamic> chat, String id, bool isMe) {
    bool isPlaying = _playingId == id;
    List<double> samples = [];
    if (chat['waveData'] != null) {
      samples = List<double>.from((chat['waveData'] as List).map((e) => e.toDouble()));
    }
    
    double currentProgress = 0.0;
    if (isPlaying && _totalDuration.inMilliseconds > 0) {
      currentProgress = _currentPosition.inMilliseconds / _totalDuration.inMilliseconds;
    }

    return Row(
      mainAxisSize: MainAxisSize.min, 
      children: [
        IconButton(
          icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle, color: const Color(0xFF075E54), size: 35), 
          onPressed: () => _playAudio(chat['fileUrl'], id)
        ),
        const SizedBox(width: 5),
        if (samples.isNotEmpty) 
          ChatWaveform(samples: samples, isMe: isMe, progress: currentProgress) 
        else 
          const Text("Voice Note", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black54))
      ]
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8), color: Colors.transparent, 
      child: Column(
        children: [
          if (_isRecording) 
            Padding(
              padding: const EdgeInsets.only(bottom: 12), 
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), 
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]), 
                child: Row(
                  mainAxisSize: MainAxisSize.min, 
                  children: [
                    const Icon(Icons.mic, color: Colors.red, size: 18), 
                    const SizedBox(width: 15), 
                    RecorderVisualizer(controller: _recorderController), 
                    const SizedBox(width: 15), 
                    const Text("Recording", style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold))
                  ]
                )
              )
            ),
            
          if (_replyMessage != null || _editingMessageId != null) 
            Container(
              margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10), 
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), 
              child: Row(
                children: [
                  Icon(_editingMessageId != null ? Icons.edit : Icons.reply, color: const Color(0xFF075E54)), 
                  const SizedBox(width: 10), 
                  Expanded(child: Text(_editingMessageId != null ? "Edit Pesan..." : (_replyMessage?['pesan'] ?? ""), maxLines: 1, overflow: TextOverflow.ellipsis)), 
                  IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _replyMessage = null; _editingMessageId = null; _etPesan.clear(); }))
                ]
              )
            ),
            
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)), 
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.add, color: Colors.grey), onPressed: _showPickerOptions), 
                      Expanded(child: TextField(controller: _etPesan, maxLines: null, decoration: const InputDecoration(hintText: "Ketik pesan...", border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 10)))), 
                      IconButton(icon: const Icon(Icons.camera_alt, color: Colors.grey), onPressed: _uploadImage)
                    ]
                  )
                )
              ),
              const SizedBox(width: 5),
              GestureDetector(
                onLongPressStart: (_) => _startRecording(), 
                onLongPressEnd: (_) => _stopRecording(), 
                child: CircleAvatar(
                  radius: 24, backgroundColor: _isRecording ? Colors.red : const Color(0xFF075E54), 
                  child: IconButton(icon: Icon(_isTyping ? Icons.send : Icons.mic, color: Colors.white), onPressed: () { if (_isTyping) _sendToFirestore(isi: _etPesan.text.trim(), tipe: "text"); })
                )
              )
            ]
          )
        ]
      )
    );
  }

  void _showSnack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }
}