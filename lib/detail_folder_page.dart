import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'full_image_slider_page.dart';
import 'loading_sultan.dart';
import 'secrets.dart';
import 'telegram_gallery_cache.dart';
import 'user_manager.dart';
import 'app_safety.dart';
import 'kategorial_config.dart';

class GalleryImage {
  final String docId;
  final String fileId;
  final DateTime? timestamp;

  const GalleryImage({
    required this.docId,
    required this.fileId,
    required this.timestamp,
  });
}

class DetailFolderPage extends StatefulWidget {
  final String folderId;
  final String folderName;
  final String? filterKategorial;

  const DetailFolderPage({
    super.key,
    required this.folderId,
    required this.folderName,
    this.filterKategorial,
  });

  @override
  State<DetailFolderPage> createState() => _DetailFolderPageState();
}

class _DetailFolderPageState extends State<DetailFolderPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  final String _botToken = teleBotTokenSecret;
  final String _chatId = "-1003815632729";

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _imageSubscription;

  final List<GalleryImage> _imageList = [];
  final Set<String> _selectedDocIds = {};

  bool _isLoading = false;
  bool _isSelectionMode = false;
  bool _isUploading = false;
  String? _loadError;
  int _uploadCurrent = 0;
  int _uploadTotal = 0;
  int _uploadSuccess = 0;
  int _uploadFailed = 0;

  late final String _collectionPath;
  String? _churchId;

  String? get _kategori {
    final value = widget.filterKategorial?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  bool get _canEditNow {
    final user = UserManager();
    final currentChurchId = user.getChurchIdForCurrentView();
    if (_churchId == null ||
        currentChurchId == null ||
        currentChurchId.trim() != _churchId) {
      return false;
    }

    if (user.isAdmin()) return true;
    final kategori = _kategori;
    return kategori != null &&
        user.isPengurus &&
        KategorialConfig.same(user.userKomisi, kategori);
  }

  @override
  void initState() {
    super.initState();
    _churchId = UserManager().getChurchIdForCurrentView()?.trim();
    _collectionPath =
        _kategori == null ? "gallery_folders" : "gallery_folders_$_kategori";
    _loadImages();
  }

  @override
  void dispose() {
    _imageSubscription?.cancel();
    super.dispose();
  }

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  DateTime? _readTimestamp(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty) return null;

    final millis = int.tryParse(value);
    if (millis != null) {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return DateTime.tryParse(value);
  }

  void _loadImages() {
    _imageSubscription?.cancel();

    final churchId = _churchId;
    if (churchId == null || churchId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = "Data gereja tidak valid.";
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    _imageSubscription = _db
        .collection("churches")
        .doc(churchId)
        .collection(_collectionPath)
        .doc(widget.folderId)
        .collection("images")
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) return;

        final temp = <GalleryImage>[];
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final fileId = data['imageUrl']?.toString().trim() ?? "";
          if (fileId.isEmpty) continue;

          temp.add(
            GalleryImage(
              docId: doc.id,
              fileId: fileId,
              timestamp: _readTimestamp(data['timestamp']),
            ),
          );
        }

        temp.sort((a, b) {
          final ad = a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bd = b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
          return ad.compareTo(bd);
        });

        final validIds = temp.map((e) => e.docId).toSet();
        _selectedDocIds.removeWhere((id) => !validIds.contains(id));
        if (_selectedDocIds.isEmpty) _isSelectionMode = false;

        setState(() {
          _imageList
            ..clear()
            ..addAll(temp);
          _isLoading = false;
          _loadError = null;
        });
      },
      onError: (Object error) {
        debugPrint("Gagal memuat foto folder: $error");
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _loadError = "Foto gagal dimuat. Periksa koneksi lalu coba lagi.";
        });
      },
    );
  }

  Future<void> _pickAndUploadImages() async {
    if (_isUploading) return;
    if (!_canEditNow) {
      _showSnack("Anda tidak memiliki izin mengunggah foto.", color: Colors.red);
      return;
    }
    if (_botToken.isEmpty || _chatId.trim().isEmpty) {
      _showSnack("Layanan upload foto belum tersedia.", color: Colors.red);
      return;
    }

    final picked = await _picker.pickMultiImage(
      imageQuality: 75,
      maxWidth: 2000,
    );
    if (picked.isEmpty) return;

    final images = picked.take(30).toList();
    if (picked.length > images.length) {
      _showSnack(
        "Maksimal 30 foto per sekali upload. ${images.length} foto akan diproses.",
      );
    }

    setState(() {
      _isUploading = true;
      _uploadCurrent = 0;
      _uploadTotal = images.length;
      _uploadSuccess = 0;
      _uploadFailed = 0;
    });

    for (var i = 0; i < images.length; i++) {
      if (!mounted) break;
      setState(() => _uploadCurrent = i + 1);

      final ok = await _uploadSingleImage(images[i]);
      if (!mounted) break;
      setState(() {
        if (ok) {
          _uploadSuccess++;
        } else {
          _uploadFailed++;
        }
      });
    }

    if (!mounted) return;
    final success = _uploadSuccess;
    final failed = _uploadFailed;

    setState(() => _isUploading = false);

    if (failed == 0) {
      _showSnack("$success foto berhasil diunggah.");
    } else {
      _showSnack(
        "$success foto berhasil, $failed foto gagal. Silakan coba ulang foto yang gagal.",
        color: Colors.orange,
      );
    }
  }

  Future<bool> _uploadSingleImage(XFile image) async {
    if (!_canEditNow) return false;

    int? telegramMessageId;
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse("https://api.telegram.org/bot$_botToken/sendPhoto"),
      );
      request.fields['chat_id'] = _chatId;
      request.files.add(
        await http.MultipartFile.fromPath('photo', image.path),
      );

      final response = await request
          .send()
          .timeout(const Duration(seconds: 90));
      final body = await response.stream.bytesToString();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint("Telegram upload ditolak: ${response.statusCode}");
        return false;
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['ok'] != true) return false;

      final result = decoded['result'];
      if (result is! Map) return false;

      final rawMessageId = result['message_id'];
      if (rawMessageId is num) {
        telegramMessageId = rawMessageId.toInt();
      }

      final photos = result['photo'];
      if (photos is! List || photos.isEmpty) return false;

      final lastPhoto = photos.last;
      if (lastPhoto is! Map) return false;

      final fileId = lastPhoto['file_id']?.toString().trim() ?? "";
      if (fileId.isEmpty) return false;

      try {
        await _saveFileIdToFirestore(fileId);
        return true;
      } catch (e) {
        debugPrint("Firestore gagal menyimpan foto galeri: $e");
        final rejected = e is StateError || (e is FirebaseException &&
            const ['permission-denied', 'unauthenticated', 'invalid-argument'].contains(e.code));
        if (rejected && telegramMessageId != null) {
          await _tryDeleteTelegramMessage(telegramMessageId);
        }
        return false;
      }
    } catch (e) {
      debugPrint("Upload foto gagal: $e");
      return false;
    }
  }

  Future<void> _saveFileIdToFirestore(String fileId) async {
    final churchId = _churchId;
    if (churchId == null || churchId.isEmpty) {
      throw StateError("Church ID tidak valid");
    }
    if (!_canEditNow) {
      throw StateError("Izin galeri berubah");
    }

    final folderRef = _db
        .collection("churches")
        .doc(churchId)
        .collection(_collectionPath)
        .doc(widget.folderId);

    final access = await ChurchWriteAccess.check(churchId, category: widget.filterKategorial);
    final imageRef = folderRef.collection('images').doc();
    await _db.runTransaction((tx) async {
      await access.inTransaction(tx);
      final folder = await tx.get(folderRef);
      if (!folder.exists) throw StateError('Folder sudah dihapus.');
      access.assertCurrent();
      tx.set(imageRef, {'imageUrl': fileId, 'timestamp': DateTime.now().millisecondsSinceEpoch});
    }).timeout(const Duration(seconds: 20));

  }

  Future<void> _tryDeleteTelegramMessage(int messageId) async {
    try {
      await http
          .post(
            Uri.parse("https://api.telegram.org/bot$_botToken/deleteMessage"),
            body: {
              "chat_id": _chatId,
              "message_id": messageId.toString(),
            },
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {}
  }

  Future<void> _deleteSelectedImages() async {
    if (!_canEditNow) {
      _showSnack("Anda tidak memiliki izin menghapus foto.", color: Colors.red);
      return;
    }

    final churchId = _churchId;
    if (churchId == null || churchId.isEmpty || _selectedDocIds.isEmpty) {
      return;
    }

    final selectedIds = _selectedDocIds.toList();
    final selectedFileIds = _imageList
        .where((image) => _selectedDocIds.contains(image.docId))
        .map((image) => image.fileId)
        .toList();

    try {
      const chunkSize = 400;
      for (var start = 0; start < selectedIds.length; start += chunkSize) {
        final end = (start + chunkSize < selectedIds.length)
            ? start + chunkSize
            : selectedIds.length;
        final batch = _db.batch();

        for (final docId in selectedIds.sublist(start, end)) {
          final ref = _db
              .collection("churches")
              .doc(churchId)
              .collection(_collectionPath)
              .doc(widget.folderId)
              .collection("images")
              .doc(docId);
          batch.delete(ref);
        }
        await batch.commit();
      }

      for (final fileId in selectedFileIds) {
        await TelegramGalleryCache.deleteCached(fileId);
      }

      _exitSelectionMode();
      _showSnack(
        "${selectedIds.length} foto dihapus dari galeri aplikasi. File Telegram lama tidak dihapus pada tahap ini.",
      );
    } catch (e) {
      debugPrint("Gagal menghapus foto: $e");
      _showSnack("Gagal menghapus foto.", color: Colors.red);
    }
  }

  Future<void> _showDeleteConfirmation() async {
    if (_selectedDocIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text("Hapus Foto?"),
            content: Text(
              "Yakin ingin menghapus ${_selectedDocIds.length} foto yang dipilih dari galeri aplikasi?",
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
        ) ??
        false;

    if (confirmed) await _deleteSelectedImages();
  }

  void _toggleSelection(String docId) {
    setState(() {
      if (_selectedDocIds.contains(docId)) {
        _selectedDocIds.remove(docId);
      } else {
        _selectedDocIds.add(docId);
      }
      _isSelectionMode = _selectedDocIds.isNotEmpty;
    });
  }

  void _enterSelectionMode(String docId) {
    if (!_canEditNow || _isUploading) return;

    setState(() {
      _isSelectionMode = true;
      _selectedDocIds.add(docId);
    });
  }

  void _toggleSelectAll() {
    if (!_canEditNow || _imageList.isEmpty) return;

    setState(() {
      if (_selectedDocIds.length == _imageList.length) {
        _selectedDocIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedDocIds
          ..clear()
          ..addAll(_imageList.map((e) => e.docId));
        _isSelectionMode = true;
      }
    });
  }

  void _exitSelectionMode() {
    if (!mounted) return;
    setState(() {
      _isSelectionMode = false;
      _selectedDocIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final churchId = _churchId;
    if (churchId == null || churchId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.folderName),
          backgroundColor: const Color(0xFF075E54),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text("Data gereja tidak valid.")),
      );
    }

    return PopScope(
      canPop: !_isSelectionMode && !_isUploading,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_isUploading) {
          _showSnack("Tunggu proses upload selesai.");
        } else if (_isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title: Text(
            _isSelectionMode
                ? "${_selectedDocIds.length} Terpilih"
                : widget.folderName,
          ),
          backgroundColor:
              _isSelectionMode ? Colors.blueGrey : const Color(0xFF075E54),
          foregroundColor: Colors.white,
          leading: _isSelectionMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _exitSelectionMode,
                )
              : null,
          actions: [
            if (_isSelectionMode)
              IconButton(
                tooltip: _selectedDocIds.length == _imageList.length
                    ? "Batal Pilih Semua"
                    : "Pilih Semua",
                onPressed: _toggleSelectAll,
                icon: const Icon(Icons.select_all),
              ),
          ],
        ),
        body: Column(
          children: [
            if (_isUploading)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Mengunggah $_uploadCurrent dari $_uploadTotal • $_uploadSuccess berhasil • $_uploadFailed gagal",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 7),
                    LinearProgressIndicator(
                      value: _uploadTotal == 0
                          ? null
                          : _uploadCurrent / _uploadTotal,
                    ),
                  ],
                ),
              ),
            Expanded(child: _buildGalleryBody()),
          ],
        ),
        floatingActionButton: !_canEditNow
            ? null
            : FloatingActionButton(
                backgroundColor:
                    _isSelectionMode ? Colors.red : const Color(0xFF075E54),
                foregroundColor: Colors.white,
                onPressed: _isUploading
                    ? null
                    : _isSelectionMode
                        ? _showDeleteConfirmation
                        : _pickAndUploadImages,
                child: _isUploading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        _isSelectionMode
                            ? Icons.delete
                            : Icons.add_photo_alternate,
                      ),
              ),
      ),
    );
  }

  Widget _buildGalleryBody() {
    if (_isLoading) {
      return const LoadingSultan(size: 80);
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 52, color: Colors.grey),
              const SizedBox(height: 12),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loadImages,
                child: const Text("COBA LAGI"),
              ),
            ],
          ),
        ),
      );
    }

    if (_imageList.isEmpty) {
      return const Center(child: Text("Folder kosong. Tambahkan foto!"));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(5),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
      ),
      itemCount: _imageList.length,
      itemBuilder: (context, index) {
        final image = _imageList[index];
        final isSelected = _selectedDocIds.contains(image.docId);

        return GestureDetector(
          onTap: () {
            if (_isSelectionMode) {
              _toggleSelection(image.docId);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FullImageSliderPage(
                    images: _imageList.map((e) => e.fileId).toList(),
                    initialIndex: index,
                  ),
                ),
              );
            }
          },
          onLongPress: () {
            if (!_isSelectionMode) {
              _enterSelectionMode(image.docId);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              TelegramGalleryItem(
                key: ValueKey(image.fileId),
                fileId: image.fileId,
                botToken: _botToken,
              ),
              if (isSelected)
                Container(
                  color: Colors.blue.withOpacity(0.5),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class TelegramGalleryItem extends StatefulWidget {
  final String fileId;
  final String botToken;

  const TelegramGalleryItem({
    super.key,
    required this.fileId,
    required this.botToken,
  });

  @override
  State<TelegramGalleryItem> createState() => _TelegramGalleryItemState();
}

class _TelegramGalleryItemState extends State<TelegramGalleryItem> {
  File? _localFile;
  bool _isError = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchImage();
  }

  Future<void> _fetchImage() async {
    if (mounted) {
      setState(() {
        _isError = false;
        _isLoading = true;
      });
    }

    try {
      final file = await TelegramGalleryCache.getOrDownload(
        fileId: widget.fileId,
        botToken: widget.botToken,
      );
      if (mounted) {
        setState(() {
          _localFile = file;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Thumbnail galeri gagal: $e");
      if (mounted) {
        setState(() {
          _localFile = null;
          _isError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_localFile != null) {
      return Image.file(
        _localFile!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _errorWidget(),
      );
    }
    if (_isError) return _errorWidget();
    if (_isLoading) {
      return Container(
        color: Colors.grey[200],
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return _errorWidget();
  }

  Widget _errorWidget() {
    return Material(
      color: Colors.grey[300],
      child: InkWell(
        onTap: _fetchImage,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, color: Colors.grey),
            SizedBox(height: 4),
            Text(
              "Coba lagi",
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

