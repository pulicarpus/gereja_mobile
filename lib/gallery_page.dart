import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'detail_folder_page.dart';
import 'loading_sultan.dart';
import 'secrets.dart';
import 'telegram_gallery_cache.dart';
import 'user_manager.dart';
import 'app_safety.dart';
import 'kategorial_config.dart';

class GalleryFolder {
  final String id;
  final String name;

  const GalleryFolder({required this.id, required this.name});
}

class GalleryPage extends StatefulWidget {
  final String? filterKategorial;

  const GalleryPage({super.key, this.filterKategorial});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _botToken = teleBotTokenSecret;

  final List<GalleryFolder> _folderList = [];
  final Map<String, Future<File?>> _coverFutures = {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _folderSubscription;

  bool _isLoading = false;
  String? _loadError;
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
    final user = UserManager();
    _churchId = user.getChurchIdForCurrentView()?.trim();
    _collectionPath =
        _kategori == null ? "gallery_folders" : "gallery_folders_$_kategori";
    _loadFolders();
  }

  @override
  void dispose() {
    _folderSubscription?.cancel();
    super.dispose();
  }

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  void _loadFolders() {
    _folderSubscription?.cancel();

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

    _folderSubscription = _db
        .collection("churches")
        .doc(churchId)
        .collection(_collectionPath)
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) return;

        final temp = snapshot.docs.map((doc) {
          final rawName = doc.data()['name']?.toString().trim() ?? "";
          return GalleryFolder(
            id: doc.id,
            name: rawName.isEmpty ? "Tanpa Nama" : rawName,
          );
        }).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

        final validIds = temp.map((e) => e.id).toSet();
        _coverFutures.removeWhere((id, _) => !validIds.contains(id));

        setState(() {
          _folderList
            ..clear()
            ..addAll(temp);
          _isLoading = false;
          _loadError = null;
        });
      },
      onError: (Object error) {
        debugPrint("Gagal memuat folder galeri: $error");
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _loadError = "Galeri gagal dimuat. Periksa koneksi lalu coba lagi.";
        });
      },
    );
  }

  Future<File?> _getFolderCover(String folderId) async {
    final churchId = _churchId;
    if (churchId == null || churchId.isEmpty || _botToken.isEmpty) return null;

    try {
      final imagesRef = _db
          .collection("churches")
          .doc(churchId)
          .collection(_collectionPath)
          .doc(folderId)
          .collection("images");

      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await imagesRef
            .orderBy("timestamp", descending: true)
            .limit(1)
            .get();
      } catch (_) {
        snap = await imagesRef.limit(1).get();
      }

      if (snap.docs.isEmpty) return null;
      final fileId =
          snap.docs.first.data()['imageUrl']?.toString().trim() ?? "";
      if (fileId.isEmpty) return null;

      return await TelegramGalleryCache.getOrDownload(
        fileId: fileId,
        botToken: _botToken,
      );
    } catch (e) {
      debugPrint("Gagal memuat cover folder $folderId: $e");
      return null;
    }
  }

  Future<File?> _coverFuture(String folderId) {
    return _coverFutures.putIfAbsent(
      folderId,
      () => _getFolderCover(folderId),
    );
  }

  Future<void> _showAddFolderDialog() async {
    if (!_canEditNow) {
      _showSnack("Anda tidak memiliki izin menambah folder.", color: Colors.red);
      return;
    }

    final churchId = _churchId;
    if (churchId == null || churchId.isEmpty) return;

    final nameCtrl = TextEditingController();
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text("Tambah Folder"),
          content: TextField(
            controller: nameCtrl,
            enabled: !saving,
            maxLength: 80,
            decoration: const InputDecoration(
              hintText: "Nama Folder",
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text("Batal"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF075E54),
                foregroundColor: Colors.white,
              ),
              onPressed: saving
                  ? null
                  : () async {
                      if (!_canEditNow) {
                        _showSnack(
                          "Izin galeri sudah berubah.",
                          color: Colors.red,
                        );
                        return;
                      }

                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        _showSnack("Nama folder wajib diisi.");
                        return;
                      }
                      final duplicate = _folderList.any(
                        (folder) => folder.name.toLowerCase() == name.toLowerCase(),
                      );
                      if (duplicate) {
                        _showSnack("Folder dengan nama yang sama sudah ada.");
                        return;
                      }

                      setDialogState(() => saving = true);
                      try {
                        final access = await ChurchWriteAccess.check(churchId, category: _kategori);
                        access.assertCurrent();
                        await _db
                            .collection("churches")
                            .doc(churchId)
                            .collection(_collectionPath)
                            .add({"name": name});
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        _showSnack("Folder berhasil ditambahkan.");
                      } catch (e) {
                        debugPrint("Gagal menambah folder: $e");
                        _showSnack(
                          "Gagal menambah folder.",
                          color: Colors.red,
                        );
                        if (dialogContext.mounted) {
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text("Simpan"),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
  }

  Future<void> _showDeleteFolderDialog(GalleryFolder folder) async {
    if (!_canEditNow) {
      _showSnack("Anda tidak memiliki izin menghapus folder.", color: Colors.red);
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text("Hapus Folder?"),
            content: Text(
              "Semua data foto di dalam '${folder.name}' akan dihapus dari galeri aplikasi. Lanjutkan?",
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

    if (!confirmed) return;
    await _deleteFolderRecursively(folder);
  }

  Future<void> _deleteFolderRecursively(GalleryFolder folder) async {
    if (!_canEditNow) {
      _showSnack("Izin galeri sudah berubah.", color: Colors.red);
      return;
    }

    final churchId = _churchId;
    if (churchId == null || churchId.isEmpty) return;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final cachedIds = <String>[];
    try {
      final access = await ChurchWriteAccess.check(churchId, category: _kategori);
      final folderRef = _db
          .collection("churches")
          .doc(churchId)
          .collection(_collectionPath)
          .doc(folder.id);
      final imagesRef = folderRef.collection("images");

      while (true) {
        access.assertCurrent();
        final page = await imagesRef.limit(400).get().timeout(const Duration(seconds: 20));
        if (page.docs.isEmpty) break;

        final batch = _db.batch();
        for (final doc in page.docs) {
          final fileId = doc.data()['imageUrl']?.toString().trim() ?? "";
          if (fileId.isNotEmpty) cachedIds.add(fileId);
          batch.delete(doc.reference);
        }
        await batch.commit().timeout(const Duration(seconds: 20));
      }

      access.assertCurrent();
      await folderRef.delete().timeout(const Duration(seconds: 20));

      for (final fileId in cachedIds) {
        await TelegramGalleryCache.deleteCached(fileId);
      }

      _coverFutures.remove(folder.id);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      _showSnack(
        "Folder dan data fotonya berhasil dihapus. File Telegram lama tetap dikelola oleh layanan media.",
      );
    } catch (e) {
      debugPrint("Gagal menghapus folder galeri: $e");
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      _showSnack(
        "Penghapusan folder belum selesai. Coba lagi.",
        color: Colors.red,
      );
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text("Bersihkan Cache Foto"),
            content: const Text(
              "File foto sementara di HP akan dihapus. Foto di server tetap aman dan akan diunduh lagi saat dibuka.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Batal"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Bersihkan"),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      final deletedCount = await TelegramGalleryCache.clearAll();
      _coverFutures.clear();
      if (mounted) setState(() {});
      _showSnack("$deletedCount file cache berhasil dibersihkan.");
    } catch (e) {
      debugPrint("Gagal membersihkan cache: $e");
      _showSnack("Gagal membersihkan cache.", color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _kategori == null ? "Galeri Foto" : "Galeri $_kategori";

    if (_churchId == null || _churchId!.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          backgroundColor: const Color(0xFF075E54),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text("Data gereja tidak valid.")),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            tooltip: "Bersihkan Cache",
            onPressed: _clearCache,
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingSultan(size: 80)
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_off,
                          size: 52,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _loadFolders,
                          child: const Text("COBA LAGI"),
                        ),
                      ],
                    ),
                  ),
                )
              : _folderList.isEmpty
                  ? Center(
                      child: Text(
                        "Belum ada folder.",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(15),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 15,
                        mainAxisSpacing: 15,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: _folderList.length,
                      itemBuilder: (context, index) {
                        final folder = _folderList[index];

                        return Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DetailFolderPage(
                                    folderId: folder.id,
                                    folderName: folder.name,
                                    filterKategorial:
                                        widget.filterKategorial,
                                  ),
                                ),
                              ).then((_) {
                                _coverFutures.remove(folder.id);
                                if (mounted) setState(() {});
                              });
                            },
                            onLongPress: _canEditNow
                                ? () => _showDeleteFolderDialog(folder)
                                : null,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: FutureBuilder<File?>(
                                    future: _coverFuture(folder.id),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        );
                                      }
                                      if (snapshot.hasData &&
                                          snapshot.data != null) {
                                        return Image.file(
                                          snapshot.data!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _folderPlaceholder(),
                                        );
                                      }
                                      return _folderPlaceholder();
                                    },
                                  ),
                                ),
                                Container(
                                  color: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 8,
                                  ),
                                  child: Text(
                                    folder.name,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
      floatingActionButton: !_canEditNow
          ? null
          : FloatingActionButton(
              backgroundColor: const Color(0xFF075E54),
              foregroundColor: Colors.white,
              onPressed: _showAddFolderDialog,
              child: const Icon(Icons.create_new_folder),
            ),
    );
  }

  Widget _folderPlaceholder() {
    return Container(
      color: Colors.indigo.shade50,
      child: const Icon(
        Icons.folder_special,
        size: 50,
        color: Colors.indigo,
      ),
    );
  }
}

