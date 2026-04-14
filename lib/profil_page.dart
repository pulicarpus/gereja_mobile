import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'user_manager.dart';
import 'loading_sultan.dart';

class ProfilPage extends StatefulWidget {
  const ProfilPage({super.key});

  @override
  State<ProfilPage> createState() => _ProfilPageState();
}

class _ProfilPageState extends State<ProfilPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _userManager = UserManager();
  
  final TextEditingController _namaController = TextEditingController();
  File? _imageFile;
  bool _isLoading = false;
  String? _currentPhotoUrl;
  String _currentRole = "Jemaat";

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  void _loadInitialData() {
    setState(() {
      _namaController.text = _userManager.userNama ?? "";
      _currentPhotoUrl = _userManager.userFotoUrl;
      _currentRole = _userManager.userRole ?? "Jemaat";
    });
  }

  // 👇 FUNGSI PILIH FOTO DARI GALERI 👇
  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70, // Kompres biar gak kegedean
    );

    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  // 👇 FUNGSI SIMPAN PERUBAHAN 👇
  Future<void> _updateProfil() async {
    if (_namaController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nama tidak boleh kosong")));
      return;
    }

    setState(() => _isLoading = true);
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      String? finalPhotoUrl = _currentPhotoUrl;

      // 1. Jika ada foto baru, upload ke Firebase Storage
      if (_imageFile != null) {
        String fileName = "profil_${user.uid}.jpg";
        Reference ref = _storage.ref().child("users/${user.uid}/$fileName");
        await ref.putFile(_imageFile!);
        finalPhotoUrl = await ref.getDownloadURL();
      }

      // 2. Update data di Firestore
      await _db.collection("users").doc(user.uid).update({
        "namaLengkap": _namaController.text.trim(),
        "photoUrl": finalPhotoUrl,
      });

      // 3. Update SharedPreferences lokal (UserManager)
      await _userManager.updateProfil(
        _namaController.text.trim(),
        finalPhotoUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profil berhasil diperbarui!")));
        Navigator.pop(context, true); // Kembali dan beri sinyal sukses
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal update: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 👇 KONFIRMASI LOGOUT 👇
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Apakah Anda yakin ingin keluar dari aplikasi?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _auth.signOut();
              OneSignal.logout();
              await _userManager.reset(); // Pastikan ada fungsi reset di UserManager
              if (mounted) {
                Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
              }
            },
            child: const Text("Ya, Keluar", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Edit Profil", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading 
          ? LoadingSultan(size: 80)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // 👇 AREA FOTO PROFIL 👇
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                          ),
                          child: CircleAvatar(
                            radius: 65,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: _imageFile != null
                                ? FileImage(_imageFile!)
                                : (_currentPhotoUrl != null 
                                    ? CachedNetworkImageProvider(_currentPhotoUrl!) 
                                    : null) as ImageProvider?,
                            child: (_imageFile == null && _currentPhotoUrl == null)
                                ? const Icon(Icons.person, size: 65, color: Colors.grey)
                                : null,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),

                  // 👇 INFO ROLE 👇
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "Status: ${_currentRole.toUpperCase()}",
                      style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 35),

                  // 👇 FORM INPUT 👇
                  TextField(
                    controller: _namaController,
                    decoration: InputDecoration(
                      labelText: "Nama Lengkap",
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // 👇 TOMBOL SIMPAN 👇
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _updateProfil,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo[900],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 2,
                      ),
                      child: const Text("SIMPAN PERUBAHAN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  
                  const SizedBox(height: 20),

                  // 👇 TOMBOL LOGOUT 👇
                  TextButton.icon(
                    onPressed: _showLogoutDialog,
                    icon: const Icon(Icons.logout, color: Colors.red),
                    label: const Text("Keluar dari Akun", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
    );
  }
}