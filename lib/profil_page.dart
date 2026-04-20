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

// 👇 IMPORT HALAMAN SINKRONISASI 👇
import 'sinkronisasi_jemaat_page.dart';

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
  bool _isLoading = true; 
  String? _currentPhotoUrl;
  String _currentRole = "Jemaat";
  bool _isLinked = false; 
  
  // WADAH UNTUK MENYIMPAN DATA BUKU INDUK
  Map<String, dynamic>? _dataBukuInduk;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    _namaController.text = _userManager.userNama ?? "";
    _currentPhotoUrl = _userManager.userFotoUrl;
    _currentRole = _userManager.userRole ?? "Jemaat";
    _isLinked = _userManager.isLinked(); 

    if (_isLinked) {
      await _fetchDataBukuInduk();
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // FUNGSI PENARIK DATA BUKU INDUK
  Future<void> _fetchDataBukuInduk() async {
    String? churchId = _userManager.getChurchIdForCurrentView();
    String? jemaatId = _userManager.jemaatId;

    if (churchId != null && jemaatId != null) {
      try {
        DocumentSnapshot doc = await _db
            .collection("churches")
            .doc(churchId)
            .collection("jemaat")
            .doc(jemaatId)
            .get();

        if (doc.exists) {
          _dataBukuInduk = doc.data() as Map<String, dynamic>?;
        }
      } catch (e) {
        debugPrint("Gagal tarik data buku induk: $e");
      }
    }
    
    if (mounted) setState(() => _isLoading = false);
  }

  // 👇 LOGIKA PRIORITAS FOTO SULTAN 👇
  String? get _displayPhotoUrl {
    // 1. Cek apakah ini foto custom yang di-upload mandiri oleh user di aplikasi
    bool isCustomUpload = _currentPhotoUrl != null && _currentPhotoUrl!.contains("profil_${_auth.currentUser?.uid}");
    
    if (isCustomUpload) {
      return _currentPhotoUrl; // Prioritas Tertinggi: Foto pilihan user sendiri
    }
    
    // 2. Cek apakah ada foto resmi dari Buku Induk (Database Firebase Admin)
    String? fotoJemaat = _dataBukuInduk?['fotoProfil'];
    if (fotoJemaat != null && fotoJemaat.isNotEmpty) {
      return fotoJemaat; // Prioritas Kedua: Foto dari Admin Gereja
    }
    
    // 3. Fallback terakhir: Foto dari Google (Gmail)
    return _currentPhotoUrl; 
  }

  // FUNGSI PILIH FOTO DARI GALERI
  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70, 
    );

    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  // FUNGSI SIMPAN PERUBAHAN NAMA & FOTO AKUN
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

      // Jika ada foto baru, upload ke Firebase Storage (Tandai dengan prefix 'profil_')
      if (_imageFile != null) {
        String fileName = "profil_${user.uid}.jpg";
        Reference ref = _storage.ref().child("users/${user.uid}/$fileName");
        await ref.putFile(_imageFile!);
        finalPhotoUrl = await ref.getDownloadURL();
      }

      // Update data di Firestore (Koleksi Users)
      await _db.collection("users").doc(user.uid).update({
        "namaLengkap": _namaController.text.trim(),
        "photoUrl": finalPhotoUrl,
      });

      // Update SharedPreferences lokal
      await _userManager.updateProfil(
        _namaController.text.trim(),
        finalPhotoUrl,
      );

      // Perbarui state _currentPhotoUrl agar UI langsung merefleksikan perubahan
      setState(() {
        _currentPhotoUrl = finalPhotoUrl;
        _imageFile = null; // Reset image file setelah sukses
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profil akun berhasil diperbarui!")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal update: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // KONFIRMASI LOGOUT
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
              await _userManager.reset(); 
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

  // NAVIGASI KE HALAMAN SINKRONISASI
  void _goToSinkronisasi() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SinkronisasiJemaatPage()),
    ).then((_) {
      setState(() => _isLoading = true);
      _userManager.loadFromPrefs().then((_) => _loadInitialData());
    });
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: Colors.indigo.shade700),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? "-" : value, 
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Profil Saya", style: TextStyle(fontWeight: FontWeight.bold)),
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
                  // --- AREA FOTO PROFIL ---
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                          ),
                          // 👇 PAKAI LOGIKA _displayPhotoUrl DI SINI 👇
                          child: CircleAvatar(
                            radius: 65,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: _imageFile != null
                                ? FileImage(_imageFile!)
                                : (_displayPhotoUrl != null 
                                    ? CachedNetworkImageProvider(_displayPhotoUrl!) 
                                    : null) as ImageProvider?,
                            child: (_imageFile == null && _displayPhotoUrl == null)
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
                  const SizedBox(height: 20),

                  // --- INFO ROLE ---
                  Text(
                    _currentRole.toUpperCase(),
                    style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 30),

                  // --- AREA STATUS SINKRONISASI ---
                  if (!_isLinked) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.orange.shade200)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 30),
                              SizedBox(width: 15),
                              Expanded(
                                child: Text("Akun Belum Terhubung", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 16)),
                              )
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text("Hubungkan akun Anda dengan data jemaat gereja untuk melihat biodata lengkap.", style: TextStyle(color: Colors.deepOrange, fontSize: 13)),
                          const SizedBox(height: 15),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _goToSinkronisasi,
                              icon: const Icon(Icons.link),
                              label: const Text("HUBUNGKAN SEKARANG"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            ),
                          )
                        ],
                      ),
                    ),
                  ],

                  // --- BIODATA LENGKAP BUKU INDUK ---
                  if (_isLinked && _dataBukuInduk != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white, 
                        borderRadius: BorderRadius.circular(20), 
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.verified_user_rounded, color: Colors.green),
                              const SizedBox(width: 10),
                              const Text("Data Buku Induk", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                              const Spacer(),
                              Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade400) 
                            ],
                          ),
                          const Divider(height: 30, thickness: 1),
                          
                          _buildInfoRow(Icons.cake, "Tanggal Lahir", _dataBukuInduk?['tanggalLahir'] ?? "-"),
                          _buildInfoRow(Icons.wc, "Jenis Kelamin", _dataBukuInduk?['jenisKelamin'] ?? "-"),
                          _buildInfoRow(Icons.phone, "Nomor Telepon", _dataBukuInduk?['nomorTelepon'] ?? "-"),
                          _buildInfoRow(Icons.location_on, "Alamat Lengkap", _dataBukuInduk?['alamat'] ?? "-"),
                          _buildInfoRow(Icons.water_drop, "Status Baptis", _dataBukuInduk?['statusBaptis'] ?? "-"),
                          _buildInfoRow(Icons.favorite, "Status Pernikahan", _dataBukuInduk?['statusPernikahan'] ?? "-"),
                          _buildInfoRow(Icons.family_restroom, "Status Keluarga", _dataBukuInduk?['statusKeluarga'] ?? "-"),
                          _buildInfoRow(Icons.groups, "Kelompok / Kategorial", _dataBukuInduk?['kelompok'] ?? "-"),
                          _buildInfoRow(Icons.star, "Karunia Pelayanan", _dataBukuInduk?['karuniaPelayanan'] ?? "-"),
                          
                          const SizedBox(height: 10),
                          Center(
                            child: Text(
                              "*Untuk mengubah data di atas, silakan hubungi Admin Gereja.",
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                              textAlign: TextAlign.center,
                            ),
                          )
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 30),

                  // --- FORM INPUT PENGATURAN AKUN ---
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Pengaturan Akun Aplikasi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _namaController,
                    decoration: InputDecoration(
                      labelText: "Nama Tampilan (Di Aplikasi)",
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // --- TOMBOL SIMPAN AKUN ---
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
                      child: const Text("SIMPAN NAMA & FOTO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  
                  const SizedBox(height: 20),

                  // --- TOMBOL LOGOUT ---
                  TextButton.icon(
                    onPressed: _showLogoutDialog,
                    icon: const Icon(Icons.logout, color: Colors.red),
                    label: const Text("Keluar dari Akun", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}