import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'package:gal/gal.dart'; // 👈 IMPORT SENJATA UNTUK NGE-SAVE KE GALERI HP

import 'secrets.dart'; 

class FullImageSliderPage extends StatefulWidget {
  final List<String> images; 
  final int initialIndex;

  const FullImageSliderPage({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  State<FullImageSliderPage> createState() => _FullImageSliderPageState();
}

class _FullImageSliderPageState extends State<FullImageSliderPage> {
  late PageController _pageController;
  int _currentIndex = 0;
  final String _botToken = teleBotTokenSecret;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      )
    );
  }

  // 👇 FUNGSI SAKTI MENYIMPAN FOTO KE GALERI HP 👇
  Future<void> _saveImageToGallery(String fileId) async {
    // Tampilkan loading muter-muter
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      // 1. Cek dulu apakah fotonya sudah ada di memori internal (cache)
      final dir = await getApplicationDocumentsDirectory();
      File localFile = File('${dir.path}/IMG_$fileId.jpg');

      // Jika belum ada di memori, download ulang dari Telegram
      if (!await localFile.exists()) {
        final urlInfo = Uri.parse("https://api.telegram.org/bot$_botToken/getFile?file_id=$fileId");
        final resInfo = await http.get(urlInfo);

        if (resInfo.statusCode == 200) {
          final json = jsonDecode(resInfo.body);
          if (json['ok'] == true) {
            String path = json['result']['file_path'];
            final downloadUrl = Uri.parse("https://api.telegram.org/file/bot$_botToken/$path");
            final imgResponse = await http.get(downloadUrl);

            if (imgResponse.statusCode == 200) {
              await localFile.writeAsBytes(imgResponse.bodyBytes);
            } else {
              throw Exception("Gagal mengunduh gambar.");
            }
          } else {
            throw Exception("Gagal mendapatkan info file.");
          }
        } else {
          throw Exception("Gagal terhubung ke server.");
        }
      }

      // 2. JURUS SULTAN: Pindahkan file ke Galeri Umum HP
      // Minta izin akses galeri dulu (kalau belum)
      bool hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        await Gal.requestAccess(toAlbum: true);
      }

      // Save fotonya ke folder "GKII Mobile"!
      await Gal.putImage(localFile.path, album: 'GKII Mobile');

      // Tutup loading
      if (mounted) Navigator.pop(context);
      _showSnack("Berhasil disimpan ke Galeri HP! 🎉");

    } catch (e) {
      // Tutup loading
      if (mounted) Navigator.pop(context);
      _showSnack("Gagal menyimpan: $e", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, 
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0, 
                child: FullscreenTelegramImage(fileId: widget.images[index]),
              );
            },
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 40, left: 10, right: 10, bottom: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    "${_currentIndex + 1} / ${widget.images.length}",
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: Colors.white, size: 28),
                    tooltip: "Simpan ke Galeri",
                    onPressed: () {
                      String currentFileId = widget.images[_currentIndex];
                      _saveImageToGallery(currentFileId);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FullscreenTelegramImage extends StatefulWidget {
  final String fileId;
  const FullscreenTelegramImage({super.key, required this.fileId});

  @override
  State<FullscreenTelegramImage> createState() => _FullscreenTelegramImageState();
}

class _FullscreenTelegramImageState extends State<FullscreenTelegramImage> {
  final String _botToken = teleBotTokenSecret;
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

      final url = Uri.parse("https://api.telegram.org/bot$_botToken/getFile?file_id=${widget.fileId}");
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['ok'] == true) {
          String path = json['result']['file_path'];
          final downloadUrl = Uri.parse("https://api.telegram.org/file/bot$_botToken/$path");
          
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
      return Image.file(_localFile!, fit: BoxFit.contain);
    }
    if (_isError) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image, color: Colors.white54, size: 60),
            SizedBox(height: 10),
            Text("Gagal memuat gambar", style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    return const Center(child: CircularProgressIndicator(color: Colors.white));
  }
}