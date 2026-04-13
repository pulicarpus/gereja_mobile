import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'user_manager.dart';
import 'main.dart'; // Asumsi main.dart berisi MainActivity kita tadi

class ValidasiGerejaPage extends StatefulWidget {
  final String userUid;
  final String userName;
  final String userEmail;

  const ValidasiGerejaPage({
    super.key,
    required this.userUid,
    required this.userName,
    required this.userEmail,
  });

  @override
  State<ValidasiGerejaPage> createState() => _ValidasiGerejaPageState();
}

class _ValidasiGerejaPageState extends State<ValidasiGerejaPage> {
  final TextEditingController _kodeController = TextEditingController();
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  bool _isLoading = false;

  void _kembaliKeLogin() async {
    await _auth.signOut();
    // Ganti dengan route login Bos
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  void _validasiDanSimpan() async {
    String kodeMasukan = _kodeController.text.trim();

    if (kodeMasukan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Masukkan kode undangan!")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Cari gereja berdasarkan kode undangan
      var query = await _db
          .collection("churches")
          .where("kodeUndangan", isEqualTo: kodeMasukan)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Kode tidak valid!")),
          );
        }
      } else {
        var docGereja = query.docs.first;
        String idGereja = docGereja.id;
        String namaGereja = docGereja.get("namaGereja") ?? "Gereja";

        _simpanUserKeFirestore(idGereja, namaGereja);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}")),
        );
      }
    }
  }

  void _simpanUserKeFirestore(String churchId, String churchName) async {
    try {
      Map<String, dynamic> dataUser = {
        "uid": widget.userUid,
        "namaLengkap": widget.userName,
        "email": widget.userEmail,
        "role": "user",
        "isBlocked": false,
        "churchId": churchId,
        "churchName": churchName,
      };

      await _db.collection("users").doc(widget.userUid).set(
            dataUser,
            SetOptions(merge: true),
          );

      // --- SINKRONISASI ONESIGNAL (Add Tag) ---
      OneSignal.User.addTagWithKey("active_church", churchId);

      // 👇 INI DIA TERSANGKANYA YANG SUDAH DIPERBAIKI BOS 👇
      // Simpan ke SharedPreferences via UserManager
      final userManager = UserManager();
      await userManager.setUser(
        role: "user",
        churchId: churchId,
        churchName: churchName,
        uId: widget.userUid, // 👈 Sudah diganti jadi uId
        uNama: widget.userName, // 👈 Sudah diganti jadi uNama
        uFoto: null, // Default kosong untuk user baru
        uKomisi: "Umum", // Default komisi
      );

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Berhasil masuk ke $churchName")),
        );
        
        // Pindah ke Halaman Utama (MainActivity)
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MainActivity()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal simpan: ${e.toString()}")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _kembaliKeLogin();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(title: const Text("Validasi Gereja")),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Selamat Datang!",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "Silakan masukkan kode undangan dari gereja Anda untuk melanjutkan.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _kodeController,
                decoration: const InputDecoration(
                  labelText: "Kode Undangan",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 20),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _validasiDanSimpan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("SIMPAN GEREJA"),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}