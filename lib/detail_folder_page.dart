import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';

import 'user_manager.dart';
import 'full_image_slider_page.dart'; // Kabel navigasi disambung!
import 'secrets.dart'; // 👈 Tambah ini
import 'loading_sultan.dart';

class GalleryImage {
  final String docId;
  final String fileId;
  final int timestamp;

  GalleryImage({required this.docId, required this.fileId, required this.timestamp});
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
  final _db = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  final String _botToken = teleBotTokenSecret;
  final String _chatId = "-1003815632729"; 

  List<GalleryImage> _imageList = [];
  bool _isLoading = false;
  late String _collectionPath;
  String? _churchId;

  bool _isSelectionMode = false;
  final Set<int> _selectedPositions = {};
  
  // Variabel untuk menyimpan hak akses
  bool _canEdit = false;

  @override
  void initState() {
    super.initState();
    _checkAccessRights(); // Cek hak akses saat halaman dibuka
    
    _churchId = UserManager().activeChurchId;
    _collectionPath = (widget.filterKategorial == null || widget.filterKategorial!.isEmpty)
        ? "gallery_folders"
        : "gallery_folders_${widget.filterKategorial}";

    _loadImages();
  }

  // 👇 SATPAM BARU: NGECEK APAKAH DIA ADMIN ATAU PENGURUS SEKSI INI 👇
  void _checkAccessRights() {
    final userManager = UserManager();
    bool isGlobalAdmin = userManager.isAdmin();
    bool isPengurusKomisiIni = false;
    
    if (widget.filterKategorial != null && widget.filterKategorial!.isNotEmpty) {
      isPengurusKomisiIni = userManager.isPengurus && (userManager.userKomisi == widget.filterKategorial);
    }
    
    setState(() {
      _canEdit = isGlobalAdmin || isPengurusKomisiIni;
    });
  }

  void _loadImages() {
    if (_churchId == null) return;
    setState(() => _isLoading = true);

    _db.collection("churches").doc(_churchId!).collection(_collectionPath)
        .doc(widget.folderId).collection("images")
        .orderBy("timestamp", descending: false)
        .snapshots().listen((snapshot) {
      if (mounted) {
        List<GalleryImage> temp = [];
        for (var doc in snapshot.docs) {
          String? fileId = doc.data()['imageUrl'];
          if (fileId != null) {
            temp.add(GalleryImage(
              docId: doc.id,
              fileId: fileId,
              timestamp: doc.data()['timestamp'] ?? 0,
            ));
          }
        }
        setState(() {
          _imageList = temp;
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _pickAndUploadImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isEmpty) return;

    _showSnack("Mengunggah ${images.length} foto... Jangan tutup halaman.");

    for (var image in images) {
      try {
        var request = http.MultipartRequest(
          'POST',
          Uri.parse("https://api.telegram.org/bot$_botToken/sendPhoto"),
        );
        request.fields['chat_id'] = _chatId;
        request.files.add(await http.MultipartFile.fromPath('photo', image.path));

        var response = await request.send();
        if (response.statusCode == 200) {
          var responseData = await response.stream.bytesToString();
          var json = jsonDecode(responseData);
          
          var photos = json['result']['photo'] as List;
          String fileId = photos.last['file_id'];
          
          _saveFileIdToFirestore(fileId);
        }
      } catch (e) {
        debugPrint("Upload error: $e");
      }
    }
    _showSnack("Selesai mengunggah!");
  }

  void _saveFileIdToFirestore(String fileId) {
    if (_churchId == null) return;
    _db.collection("churches").doc(_churchId!).collection(_collectionPath)
        .doc(widget.folderId).collection("images").add({
      "imageUrl": fileId,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _deleteSelectedImages() {
    if (_churchId == null) return;

    for (int pos in _selectedPositions) {
      String docId = _imageList[pos].docId;
      _db.collection("churches").doc(_churchId!).collection(_collectionPath)
          .doc(widget.folderId).collection("images").doc(docId).delete();
    }
    _exitSelectionMode();
    _showSnack("Foto berhasil dihapus");
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus Foto?"),
        content: Text("Yakin ingin menghapus ${_selectedPositions.length} foto yang dipilih?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              _deleteSelectedImages();
            },
            child: const Text("Hapus"),
          ),
        ],
      ),
    );
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedPositions.contains(index)) {
        _selectedPositions.remove(index);
        if (_selectedPositions.isEmpty) _isSelectionMode = false;
      } else {
        _selectedPositions.add(index);
      }
    });
  }

  void _enterSelectionMode(int index) {
    // 👇 PASTIKAN HANYA YANG PUNYA HAK AKSES YANG BISA HAPUS FOTO 👇
    if (!_canEdit) return; 
    
    setState(() {
      _isSelectionMode = true;
      _selectedPositions.add(index);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedPositions.clear();
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvoked: (didPop) {
        if (!didPop) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title: Text(_isSelectionMode ? "${_selectedPositions.length} Terpilih" : widget.folderName),
          backgroundColor: _isSelectionMode ? Colors.blueGrey : const Color(0xFF075E54),
          foregroundColor: Colors.white,
          leading: _isSelectionMode
              ? IconButton(icon: const Icon(Icons.close), onPressed: _exitSelectionMode)
              : null,
        ),
        body: _isLoading
            ? const LoadingSultan(size: 80)
            : _imageList.isEmpty
                ? const Center(child: Text("Folder kosong. Tambahkan foto!"))
                : GridView.builder(
                    padding: const EdgeInsets.all(5),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, 
                      crossAxisSpacing: 5,
                      mainAxisSpacing: 5,
                    ),
                    itemCount: _imageList.length,
                    itemBuilder: (context, index) {
                      bool isSelected = _selectedPositions.contains(index);
                      return GestureDetector(
                        onTap: () {
                          if (_isSelectionMode) {
                            _toggleSelection(index);
                          } else {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => FullImageSliderPage(
                              images: _imageList.map((e) => e.fileId).toList(),
                              initialIndex: index,
                            )));
                          }
                        },
                        onLongPress: () {
                          if (!_isSelectionMode) _enterSelectionMode(index);
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            TelegramGalleryItem(fileId: _imageList[index].fileId, botToken: _botToken),
                            if (isSelected)
                              Container(
                                color: Colors.blue.withOpacity(0.5),
                                alignment: Alignment.center,
                                child: const Icon(Icons.check_circle, color: Colors.white, size: 40),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  
        // 👇 SEKARANG TOMBOL INI MUNCUL JIKA `_canEdit` TRUE (ADMIN ATAU PENGURUS SEKSI) 👇
        floatingActionButton: !_canEdit ? null : FloatingActionButton(
          backgroundColor: _isSelectionMode ? Colors.red : const Color(0xFF075E54),
          foregroundColor: Colors.white,
          onPressed: _isSelectionMode ? _showDeleteConfirmation : _pickAndUploadImages,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Icon(
              _isSelectionMode ? Icons.delete : Icons.add_photo_alternate,
              key: ValueKey<bool>(_isSelectionMode),
            ),
          ),
        ),
      ),
    );
  }
}

class TelegramGalleryItem extends StatefulWidget {
  final String fileId;
  final String botToken;

  const TelegramGalleryItem({super.key, required this.fileId, required this.botToken});

  @override
  State<TelegramGalleryItem> createState() => _TelegramGalleryItemState();
}

class _TelegramGalleryItemState extends State<TelegramGalleryItem> {
  File? _localFile;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _fetchImage();
  }

  Future<void> _fetchImage() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/IMG_${widget.fileId}.jpg');

      if (await file.exists()) {
        if (mounted) setState(() => _localFile = file);
        return;
      }

      final url = Uri.parse("https://api.telegram.org/bot${widget.botToken}/getFile?file_id=${widget.fileId}");
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['ok'] == true) {
          String path = json['result']['file_path'];
          final downloadUrl = Uri.parse("https://api.telegram.org/file/bot${widget.botToken}/$path");
          
          final imgResponse = await http.get(downloadUrl);
          if (imgResponse.statusCode == 200) {
            await file.writeAsBytes(imgResponse.bodyBytes);
            if (mounted) setState(() => _localFile = file);
            return;
          }
        }
      }
      if (mounted) setState(() => _isError = true);
    } catch (e) {
      if (mounted) setState(() => _isError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_localFile != null) {
      return Image.file(_localFile!, fit: BoxFit.cover);
    }
    if (_isError) {
      return Container(color: Colors.grey[300], child: const Icon(Icons.broken_image, color: Colors.grey));
    }
    return Container(
      color: Colors.grey[200],
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}