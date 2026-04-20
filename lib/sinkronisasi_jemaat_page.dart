import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_manager.dart';
import 'main.dart'; // Asumsi main.dart berisi MainActivity kita

class SinkronisasiJemaatPage extends StatefulWidget {
  const SinkronisasiJemaatPage({super.key});

  @override
  State<SinkronisasiJemaatPage> createState() => _SinkronisasiJemaatPageState();
}

class _SinkronisasiJemaatPageState extends State<SinkronisasiJemaatPage> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  
  final _phoneController = TextEditingController();
  final _securityController = TextEditingController(); // Untuk input Tahun Lahir
  
  bool _isLoading = false;
  Map<String, dynamic>? _dataJemaatDitemukan;
  String? _jemaatDocId;

  // FUNGSI 1: MENCARI DATA BERDASARKAN NOMOR HP
  Future<void> _cariNomorWA() async {
    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();
    
    String inputNumber = _phoneController.text.trim();
    if (inputNumber.isEmpty) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Masukkan nomor WhatsApp dulu Bos!")));
      return;
    }

    // Normalisasi awalan nomor HP
    if (inputNumber.startsWith("62")) inputNumber = "0${inputNumber.substring(2)}";
    if (inputNumber.startsWith("+62")) inputNumber = "0${inputNumber.substring(3)}";

    final churchId = UserManager().getChurchIdForCurrentView();
    if (churchId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      var query = await _db
          .collection("churches")
          .doc(churchId)
          .collection("jemaat")
          .where("nomorTelepon", isEqualTo: inputNumber)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        setState(() {
          _jemaatDocId = query.docs.first.id;
          _dataJemaatDitemukan = query.docs.first.data();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nomor WA tidak ditemukan di buku induk gereja.")));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // FUNGSI 2: VERIFIKASI BIODATA (TAHUN LAHIR) & AUTO-LINK
  Future<void> _verifikasiDanHubungkan() async {
    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();

    String inputTahun = _securityController.text.trim();
    String? tanggalLahirAsli = _dataJemaatDitemukan?['tanggalLahir']; // Contoh format Admin: "15-08-1985"

    if (tanggalLahirAsli == null || tanggalLahirAsli.isEmpty) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data tanggal lahir Anda belum diisi Admin. Silakan hubungi Admin Gereja.")));
      return;
    }

    // Cek apakah input jemaat (misal "1985") ada di dalam string tanggal lahir asli
    if (tanggalLahirAsli.contains(inputTahun) && inputTahun.length == 4) {
      // ✅ VERIFIKASI BERHASIL! LANGSUNG HUBUNGKAN!
      final user = _auth.currentUser;
      final churchId = UserManager().getChurchIdForCurrentView();

      if (user != null && churchId != null && _jemaatDocId != null) {
        try {
          // 1. Update di Data Jemaat (Tanamkan UID User)
          await _db.collection("churches").doc(churchId).collection("jemaat").doc(_jemaatDocId).update({
            "uid": user.uid,
          });

          // 2. Update di Profil User (Tanamkan ID Jemaat)
          await _db.collection("users").doc(user.uid).set({
            "jemaatId": _jemaatDocId,
          }, SetOptions(merge: true));

          // 3. Update di Memori Lokal (UserManager)
          await UserManager().linkJemaatId(_jemaatDocId!);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Verifikasi Berhasil! Akun Anda kini berstatus Sultan! 🎉")));
            Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const MainActivity()), (route) => false);
          }
        } catch (e) {
          setState(() => _isLoading = false);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal menghubungkan: $e")));
        }
      }
    } else {
      // ❌ VERIFIKASI GAGAL
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tahun Lahir salah! Silakan coba lagi.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Hubungkan Data Jemaat"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(_dataJemaatDitemukan == null ? Icons.contact_phone : Icons.verified_user_rounded, size: 80, color: Colors.indigo),
            const SizedBox(height: 20),
            
            // ==========================================
            // TAHAP 1: CARI NOMOR WA
            // ==========================================
            if (_dataJemaatDitemukan == null) ...[
              const Text("Masukkan Nomor HP/WA", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text("Gunakan nomor yang didaftarkan ke gereja untuk mengeklaim buku induk digital Anda.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.phone_android),
                  labelText: "Nomor HP (Cth: 0812...)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
              const SizedBox(height: 20),
              
              SizedBox(
                width: double.infinity, height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _cariNomorWA,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("CARI DATA SAYA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ] 
            
            // ==========================================
            // TAHAP 2: VERIFIKASI KEAMANAN
            // ==========================================
            else ...[
              const Text("Data Ditemukan! 🎉", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(height: 20),
              
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.green.shade200)),
                child: Column(
                  children: [
                    Text(_dataJemaatDitemukan?['namaLengkap'] ?? "-", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                    const SizedBox(height: 5),
                    Text("Kelompok: ${_dataJemaatDitemukan?['kelompok'] ?? "-"}"),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              
              const Text("Untuk memastikan ini benar-benar Anda, jawab pertanyaan keamanan berikut:", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              
              TextField(
                controller: _securityController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.cake),
                  labelText: "Tahun Lahir Anda (Cth: 1985)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
              const SizedBox(height: 10),
              
              SizedBox(
                width: double.infinity, height: 55,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _verifikasiDanHubungkan,
                  icon: const Icon(Icons.link),
                  label: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("VERIFIKASI & HUBUNGKAN", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                ),
              ),
              
              const SizedBox(height: 15),
              TextButton(
                onPressed: () => setState(() { _dataJemaatDitemukan = null; _phoneController.clear(); _securityController.clear(); }), 
                child: const Text("Bukan data saya, cari ulang", style: TextStyle(color: Colors.red))
              )
            ],
            
            const SizedBox(height: 40),

            // 👇 PINTU DARURAT (GUEST MODE) 👇
            TextButton(
              onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => const MainActivity()), (route) => false), 
              child: const Text("Lewati sementara (Masuk ke Beranda)", style: TextStyle(color: Colors.grey, decoration: TextDecoration.underline))
            )
          ],
        ),
      ),
    );
  }
}