import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import 'secrets.dart';
import 'telegram_gallery_cache.dart';

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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final maxIndex = widget.images.isEmpty ? 0 : widget.images.length - 1;
    _currentIndex = widget.initialIndex.clamp(0, maxIndex).toInt();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _saveImageToGallery(String fileId) async {
    if (_isSaving) return;
    if (_botToken.isEmpty) {
      _showSnack("Layanan foto belum tersedia.", isError: true);
      return;
    }

    setState(() => _isSaving = true);

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    try {
      final localFile = await TelegramGalleryCache.getOrDownload(
        fileId: fileId,
        botToken: _botToken,
      );

      var hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        await Gal.requestAccess(toAlbum: true);
        hasAccess = await Gal.hasAccess(toAlbum: true);
      }

      if (!hasAccess) {
        throw const FileSystemException(
          "Izin menyimpan foto ke galeri ditolak.",
        );
      }

      await Gal.putImage(localFile.path, album: 'GKII Mobile');

      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      _showSnack("Foto berhasil disimpan ke Galeri HP.");
    } catch (e) {
      debugPrint("Gagal menyimpan foto ke galeri HP: $e");
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      _showSnack(
        e is FileSystemException
            ? e.message
            : "Gagal menyimpan foto. Coba lagi.",
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text(
            "Foto tidak tersedia.",
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            allowImplicitScrolling: true,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              final fileId = widget.images[index];
              return InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: FullscreenTelegramImage(
                  key: ValueKey(fileId),
                  fileId: fileId,
                ),
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.only(
                top: 40,
                left: 10,
                right: 10,
                bottom: 10,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    "${_currentIndex + 1} / ${widget.images.length}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: _isSaving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.download_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                    tooltip: "Simpan ke Galeri",
                    onPressed: _isSaving
                        ? null
                        : () => _saveImageToGallery(
                              widget.images[_currentIndex],
                            ),
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

  const FullscreenTelegramImage({
    super.key,
    required this.fileId,
  });

  @override
  State<FullscreenTelegramImage> createState() =>
      _FullscreenTelegramImageState();
}

class _FullscreenTelegramImageState
    extends State<FullscreenTelegramImage> {
  final String _botToken = teleBotTokenSecret;
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
        botToken: _botToken,
      );
      if (mounted) {
        setState(() {
          _localFile = file;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Fullscreen foto gagal dimuat: $e");
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
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _errorWidget(),
      );
    }

    if (_isError) return _errorWidget();

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return _errorWidget();
  }

  Widget _errorWidget() {
    return Center(
      child: InkWell(
        onTap: _fetchImage,
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image,
                color: Colors.white54,
                size: 60,
              ),
              SizedBox(height: 10),
              Text(
                "Gagal memuat gambar",
                style: TextStyle(color: Colors.white54),
              ),
              SizedBox(height: 6),
              Text(
                "Ketuk untuk mencoba lagi",
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
