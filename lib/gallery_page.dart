import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'secrets.dart'; // 👈 Tambah ini di paling atas

import 'user_manager.dart';
import 'detail_folder_page.dart'; // Kabel navigasi disambung!

class GalleryFolder {
  final String id;
  final String name;

  GalleryFolder({required this.id, required this.name});
}

class GalleryPage extends StatefulWidget {
  final String? filterKategorial;
  const GalleryPage({super.key, this.filterKategorial});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final _db = FirebaseFirestore.instance;
  // Ganti hardcode jadi variabel dari secrets.dart
  final String _botToken = teleBotTokenSecret;

  List<GalleryFolder> _folderList = [];
  bool _isLoading = false;
  late String _collectionPath;
  String? _churchId;

  @override
  void initState() {
    super.initState();
    _churchId = UserManager().activeChurchId;
    
    _collectionPath = (widget.filterKategorial == null || widget.filterKategorial!.isEmpty) 
        ? "gallery_folders" 
        : "gallery_folders_${widget.filterKategorial}";
        
    _loadFolders();
  }

  void _loadFolders() {
    if (_churchId == null) return;
    setState(() => _isLoading = true);

    _db.collection("churches").doc(_churchId!).collection(_collectionPath)
       .snapshots().listen((snapshot) {
      if (mounted) {
        List<GalleryFolder> temp = [];
        for (var doc in snapshot.docs) {
          temp.add(GalleryFolder(id: doc.id, name: doc.data()['name'] ?? "Tanpa Nama"));
        }
        setState(() {
          _folderList = temp;
          _isLoading = false;
        });
      }
    });
  }

  Future<File?> _getFolderCover(String folderId) async {
    if (_churchId == null) return null;

    try {
      var snap = await _db.collection("churches").doc(_churchId!)
          .collection(_collectionPath).doc(folderId).collection("images")
          .orderBy("timestamp", descending: true).limit(1).get();

      if (snap.docs.isEmpty) return null;
      
      String? fileId = snap.docs.first.data()['imageUrl'];
      if (fileId == null || fileId.isEmpty) return null;

      final dir = await getApplicationDocumentsDirectory();
      final File localFile = File('${dir.path}/IMG_$fileId.jpg');
      
      if (await localFile.exists()) return localFile;

      final url = Uri.parse("https://api.telegram.org/bot$_botToken/getFile?file_id=$fileId");
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['ok'] == true) {
          String path = json['result']['file_path'];
          final downloadUrl = Uri.parse("https://api.telegram.org/file/bot$_botToken/$path");
          
          final imgResponse = await http.get(downloadUrl);
          if (imgResponse.statusCode == 200) {
            await localFile.writeAsBytes(imgResponse.bodyBytes); 
            return localFile;
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching cover: $e");
    }
    return null;
  }

  void _showAddFolderDialog() {
    final TextEditingController nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Tambah Folder"),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(hintText: "Nama Folder", border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF075E54), foregroundColor: Colors.white),
            onPressed: () {
              String name = nameCtrl.text.trim();
              if (name.isNotEmpty && _churchId != null) {
                _db.collection("churches").doc(_churchId!).collection(_collectionPath).add({"name": name});
                Navigator.pop(context);
              }
            },
            child: const Text("Simpan"),
          ),
        ],
      ),
    );
  }

  void _showDeleteFolderDialog(GalleryFolder folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus Folder?"),
        content: Text("Semua foto di dalam '${folder.name}' akan hilang. Lanjutkan?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              _db.collection("churches").doc(_churchId!).collection(_collectionPath).doc(folder.id).delete();
              Navigator.pop(context);
            },
            child: const Text("Hapus"),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCache() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Bersihkan Memori"),
        content: const Text("Tindakan ini akan menghapus semua file foto sementara di HP Anda. Foto di server tetap aman. Lanjutkan?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context);
              int deletedCount = 0;
              try {
                final dir = await getApplicationDocumentsDirectory();
                final files = dir.listSync();
                for (var file in files) {
                  if (file is File && file.path.contains("IMG_")) {
                    await file.delete();
                    deletedCount++;
                  }
                }
                _showSnack("$deletedCount file cache berhasil dibersihkan!");
                setState(() {}); 
              } catch (e) {
                _showSnack("Gagal membersihkan cache.");
              }
            },
            child: const Text("Bersihkan"),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    bool isAdmin = UserManager().isAdmin();
    String title = (widget.filterKategorial == null || widget.filterKategorial!.isEmpty) 
        ? "Galeri Foto" 
        : "Galeri ${widget.filterKategorial}";

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            tooltip: "Bersihkan Memori",
            onPressed: _clearCache,
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _folderList.isEmpty
          ? Center(child: Text("Belum ada folder.", style: TextStyle(color: Colors.grey[600])))
          : GridView.builder(
              padding: const EdgeInsets.all(15),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, 
                crossAxisSpacing: 15, 
                mainAxisSpacing: 15, 
                childAspectRatio: 0.85 
              ),
              itemCount: _folderList.length,
              itemBuilder: (context, index) {
                var folder = _folderList[index];
                
                return Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  clipBehavior: Clip.antiAlias, 
                  child: InkWell(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => DetailFolderPage(
                        folderId: folder.id,
                        folderName: folder.name,
                        filterKategorial: widget.filterKategorial,
                      )));
                    },
                    onLongPress: isAdmin ? () => _showDeleteFolderDialog(folder) : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: FutureBuilder<File?>(
                            future: _getFolderCover(folder.id),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                              } else if (snapshot.hasData && snapshot.data != null) {
                                return Image.file(snapshot.data!, fit: BoxFit.cover);
                              } else {
                                return Container(
                                  color: Colors.indigo.shade50,
                                  child: const Icon(Icons.folder_special, size: 50, color: Colors.indigo),
                                );
                              }
                            },
                          ),
                        ),
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          child: Text(
                            folder.name, 
                            textAlign: TextAlign.center, 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
            
      floatingActionButton: !isAdmin ? null : FloatingActionButton(
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        child: const Icon(Icons.create_new_folder),
        onPressed: _showAddFolderDialog,
      ),
    );
  }
}