import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'user_manager.dart';
import 'app_safety.dart';
import 'profile_service.dart';


// 👇 IMPORT HALAMAN SINKRONISASI KITA 👇
import 'sinkronisasi_jemaat_page.dart'; 

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

  Future<void> _kembaliKeLogin() async {
    if (_isLoading || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await _auth.signOut().timeout(const Duration(seconds: 20));
      try { await Future<void>.sync(OneSignal.logout).timeout(const Duration(seconds: 10)); } catch (_) {}
      await UserManager().reset().timeout(const Duration(seconds: 10));
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(profileError(e))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _validasiDanSimpan() async {
    if (_isLoading || !mounted) return;
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
          .limit(2)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      if (!mounted || _auth.currentUser?.uid != widget.userUid) return;

      if (query.docs.isEmpty) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Kode tidak valid!")),
          );
        }
      } else if (query.docs.length != 1) {
        throw StateError('Kode undangan dipakai lebih dari satu gereja. Hubungi Admin Gereja.');
      } else {
        var docGereja = query.docs.first;
        String idGereja = docGereja.id;
        
        // 👇 JARING PENGAMAN ANTI-CRASH SULTAN 👇
        // Ubah doc jadi Map dulu, biar aman ngecek datanya
        Map<String, dynamic>? dataGereja = docGereja.data();
        
        // Cek kalau field namaGereja beneran ada, kalau nggak ada otomatis kasih nama "Gereja"
        String namaGereja = "Gereja";
        if (dataGereja.containsKey('namaGereja') && dataGereja['namaGereja'] != null) {
            namaGereja = dataGereja['namaGereja'].toString();
        }

        await _simpanUserKeFirestore(idGereja, namaGereja, kodeMasukan);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(profileError(e))),
        );
      }
    }
    finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _simpanUserKeFirestore(String churchId, String churchName, String invitationCode) async {
    try {
      Map<String, dynamic> dataUser = {
        "uid": widget.userUid,
        "namaLengkap": widget.userName,
        "email": widget.userEmail,
        "role": "user",
        "isBlocked": false,
        "churchId": churchId,
        "churchName": churchName,
        "jemaatId": "", // 👈 DEFAULT KOSONG DULU
        "isPengurus": false // 👈 DEFAULT USER BIASA
      };

      final ref = _db.collection("users").doc(widget.userUid);
      final saved = await _db.runTransaction<Map<String, dynamic>>((tx) async {
        final existing = await tx.get(ref);
        final church = await tx.get(_db.collection("churches").doc(churchId));
        if (_auth.currentUser?.uid != widget.userUid) throw StateError("Sesi berubah.");
        if (!church.exists || church.data()?['kodeUndangan'] != invitationCode) {
          throw StateError("Kode undangan sudah berubah. Periksa kembali.");
        }
        if (existing.exists) {
          final account = existing.data()!;
          final patch = registrationChurchPatch(account, churchId, churchName);
          tx.update(ref, patch);
          return {...account, ...patch};
        } else {
          tx.set(ref, dataUser);
          return dataUser;
        }
      }).timeout(const Duration(seconds: 20));
      if (!mounted || _auth.currentUser?.uid != widget.userUid) return;

      // --- SINKRONISASI ONESIGNAL (Add Tag) ---
      try { OneSignal.User.addTagWithKey("active_church", churchId); } catch (_) {}

      // Simpan ke SharedPreferences via UserManager
      final userManager = UserManager();
      await userManager.setUser(
        role: saved['role']?.toString() ?? "user",
        churchId: churchId,
        churchName: churchName,
        uId: widget.userUid, 
        uNama: saved['namaLengkap']?.toString() ?? widget.userName, 
        uFoto: saved['photoUrl']?.toString() ?? _auth.currentUser?.photoURL, 
        uKomisi: saved['kelompok']?.toString() ?? "Umum", 
        uAdminDaerahArea: saved['adminDaerahArea']?.toString(),
        uDaerah: saved['daerah']?.toString(),
        uJemaatId: saved['jemaatId']?.toString(),
        uIsPengurus: saved['isPengurus'] == true, // 👈 SESUAIKAN DENGAN LOGIKA USER MANAGER BARU
      ).timeout(const Duration(seconds: 10));

      if (mounted && _auth.currentUser?.uid == widget.userUid) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Berhasil masuk ke $churchName")),
        );
        
        // 👇 PENGALIHAN JALUR SULTAN: KE SINKRONISASI DULU 👇
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const SinkronisasiJemaatPage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(profileError(e))),
        );
      }
    }
  }

  @override
  void dispose() {
    _kodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (!_isLoading) _kembaliKeLogin();
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
                enabled: !_isLoading,
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
