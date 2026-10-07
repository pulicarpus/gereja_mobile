import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'desktop_google_login.dart';
import 'alkitab_page.dart';
import 'mobile_notifications.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'user_manager.dart';

import 'validasi_gereja_page.dart';
import 'sinkronisasi_jemaat_page.dart'; 
import 'loading_sultan.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  bool _isLoading = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final DesktopGoogleLogin _desktopLogin = DesktopGoogleLogin();

  @override void dispose() { _desktopLogin.cancel(); super.dispose(); }

  Future<void> _signInWithGoogle() async {
    if (_isLoading || !mounted) return;
    setState(() => _isLoading = true);
    try {
      UserCredential userCredential;
      if (Platform.isWindows) {
        final config = await DesktopGoogleLogin.readConfig(Firebase.app().options.projectId);
        if (!mounted) return;
        final tokens = await _desktopLogin.signIn(clientId: config['client_id']!, clientSecret: config['client_secret']);
        if (!mounted) return;
        userCredential = await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: tokens.idToken, accessToken: tokens.accessToken));
      } else {
        await _googleSignIn.signOut();
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) return;
        final googleAuth = await googleUser.authentication;
        userCredential = await _auth.signInWithCredential(GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken));
      }
      final User? user = userCredential.user;

      if (user != null) {
        MobilePush.login(user.uid);
        await _checkUserRegistration(user);
      }
    } catch (e) {
      _showToast(e is StateError ? e.message.toString() : "Login belum berhasil. Periksa koneksi atau coba kembali.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkUserRegistration(User user) async {
    try {
      final doc = await _db.collection("users").doc(user.uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      if (!mounted || _auth.currentUser?.uid != user.uid) return;

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['isBlocked'] == true) {
          await _auth.signOut();
          MobilePush.logout();
          await UserManager().reset();
          if (!mounted) return;
          _showToast("Akun Anda sedang dinonaktifkan. Hubungi administrator gereja.");
          setState(() => _isLoading = false);
          return;
        }

        String role = data['role']?.toString() ?? "user";
        String? churchId = data['churchId']?.toString(); 
        String? jemaatId = data['jemaatId']?.toString(); 
        String churchName = data['churchName']?.toString() ?? "";
        String nama = data['namaLengkap']?.toString() ?? user.displayName ?? "Jemaat";
        String? foto = data['photoUrl']?.toString() ?? user.photoURL;
        bool statusPengurus = data['isPengurus'] == true;
        
        // 👇 AMBIL DATA DAERAH DARI FIRESTORE 👇
        String daerah = data['daerah']?.toString() ?? ""; 

        await UserManager().setUser(
          role: role,
          churchId: churchId ?? "",
          churchName: churchName,
          uId: user.uid,
          uNama: nama,
          uFoto: foto,
          uKomisi: data['kelompok']?.toString() ?? "Umum",
          uIsPengurus: statusPengurus, 
          uJemaatId: jemaatId,
          uAdminDaerahArea: data['adminDaerahArea']?.toString(),
          uDaerah: data['daerah']?.toString(),
        );

        if (!mounted || _auth.currentUser?.uid != user.uid) return;

        // 👇 PENANAMAN TAG ONESIGNAL SULTAN (UNTUK NOTIF EKSKLUSIF) 👇
        MobilePush.tag("role", role);
        MobilePush.tag("kelompok", data['kelompok']?.toString() ?? "Umum");
        if (daerah.isNotEmpty) {
          MobilePush.tag("daerah", daerah);
        }

        // Jika Superadmin, beri Tag khusus di OneSignal
        if (role == "superadmin") {
          MobilePush.tag("active_church", "SUPERADMIN");
          _goToMainActivity(); 
          return;
        } else if (churchId != null && churchId.isNotEmpty) {
          MobilePush.tag("active_church", churchId);
        }

        // LOGIKA SATPAM 3 JALUR SULTAN
        if (churchId == null || churchId.trim().isEmpty) {
          _goToValidasiManual(user);
        } else if (jemaatId == null || jemaatId.trim().isEmpty) {
          _goToSinkronisasi();
        } else {
          _goToMainActivity();
        }

      } else {
        await _saveNewUserAndValidate(user);
      }
    } catch (e) {
      debugPrint("Error checkUser: $e");
      _showToast("Akun belum dapat diperiksa. Periksa koneksi lalu coba lagi.");
    }
  }

  Future<void> _saveNewUserAndValidate(User user) async {
    final newUser = {
      "uid": user.uid,
      "email": user.email,
      "namaLengkap": user.displayName,
      "photoUrl": user.photoURL, 
      "role": "user",
      "isBlocked": false,
      "churchId": "",
      "churchName": "",
      "jemaatId": "", 
      "isPengurus": false,
      "daerah": "" // 👈 DEFAULT KOSONG UNTUK USER BARU
    };

    try {
      final ref = _db.collection("users").doc(user.uid);
      await _db.runTransaction((tx) async {
        final existing = await tx.get(ref);
        if (_auth.currentUser?.uid != user.uid) throw StateError("Sesi berubah.");
        if (!existing.exists) tx.set(ref, newUser);
      }).timeout(const Duration(seconds: 20));
      if (!mounted || _auth.currentUser?.uid != user.uid) return;
      await _checkUserRegistration(user);
    } catch (e) {
      _showToast("Pendaftaran belum dapat dipastikan. Coba masuk kembali.");
    }
  }

  void _goToValidasiManual(User user) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    _showToast("Silakan masukkan kode undangan gereja Anda.");
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ValidasiGerejaPage(
          userUid: user.uid,
          userName: user.displayName ?? "Jemaat Baru",
          userEmail: user.email ?? "",
        ),
      ),
    );
  }

  void _goToSinkronisasi() {
    if (!mounted) return;
    setState(() => _isLoading = false);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const SinkronisasiJemaatPage()),
    );
  }

  void _goToMainActivity() {
    if (!mounted) return;
    setState(() => _isLoading = false);
    Navigator.pushReplacementNamed(context, '/home');
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading 
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            LoadingSultan(size: 80),
            if (Platform.isWindows) TextButton(onPressed: _desktopLogin.cancel, child: const Text('Batalkan login')),
          ]))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(30),
            child: Column(
              children: [
                if (Platform.isWindows) const Text('GKII Mobile untuk Windows — versi uji'),
                const SizedBox(height: 80),
                const Icon(Icons.church, size: 80, color: Colors.indigo),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _signInWithGoogle,
                    icon: const Icon(Icons.g_mobiledata, size: 30),
                    label: const Text("Masuk dengan Google"),
                  ),
                ),
                if (Platform.isWindows) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AlkitabPage())),
                    icon: const Icon(Icons.menu_book), label: const Text('Buka Alkitab lokal')),
                  const Text('Login membuka browser. Gunakan akun Google yang sama dengan aplikasi Android.', textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
    );
  }
}

