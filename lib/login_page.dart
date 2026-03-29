import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'user_manager.dart'; // File yang kita buat sebelumnya

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  bool _isLoading = false;

  // Konfigurasi Google Sign In
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // 1. FUNGSI LOGIN GOOGLE
  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        // SINKRONISASI 1: Login ke OneSignal
        OneSignal.login(user.uid);
        _checkUserRegistration(user);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Google Login Gagal: $e")),
      );
    }
  }

  // 2. FUNGSI LOGIN MANUAL (EMAIL/PASS)
  Future<void> _loginManual() async {
    final email = _emailController.text.trim();
    final pass = _passController.text.trim();

    if (email.isEmpty || pass.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );
      final User? user = userCredential.user;

      if (user != null) {
        OneSignal.login(user.uid);
        _checkUserRegistration(user);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Login Manual Gagal. Cek Email/Password.")),
      );
    }
  }

  // 3. CEK REGISTRASI DI FIRESTORE
  Future<void> _checkUserRegistration(User user) async {
    try {
      DocumentSnapshot doc = await _db.collection("users").document(user.uid).get();

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String? churchId = data['churchId'];

        if (churchId != null && churchId.isNotEmpty) {
          // SINKRONISASI 2: Tambah Tag OneSignal
          OneSignal.User.addTagWithKey("active_church", churchId);

          // Simpan ke Session UserManager
          await UserManager().setUser(
            role: data['role'] ?? "user",
            churchId: churchId,
            churchName: data['churchName'] ?? "",
            uId: user.uid,
            uNama: data['namaLengkap'] ?? user.displayName ?? "",
            uFoto: user.photoURL,
          );

          _goToMainActivity();
        } else {
          _goToValidasiManual(user);
        }
      } else {
        _saveNewUserAndValidate(user);
      }
    } catch (e) {
      _goToValidasiManual(user);
    }
  }

  // 4. SIMPAN USER BARU KE FIRESTORE
  Future<void> _saveNewUserAndValidate(User user) async {
    final newUser = {
      "uid": user.uid,
      "email": user.email,
      "namaLengkap": user.displayName,
      "photoUrl": user.photoURL,
      "role": "user",
      "isBlocked": false,
      "churchId": "",
      "churchName": ""
    };

    try {
      await _db.collection("users").document(user.uid).set(newUser, SetOptions(merge: true));
      _goToValidasiManual(user);
    } catch (e) {
      _goToValidasiManual(user);
    }
  }

  void _goToMainActivity() {
    setState(() => _isLoading = false);
    // Ganti dengan route Dashboard Bos
    Navigator.pushReplacementNamed(context, '/main');
  }

  void _goToValidasiManual(User user) {
    setState(() => _isLoading = false);
    // Navigator.push ke halaman ValidasiGereja
    print("Pindah ke Validasi Gereja untuk UID: ${user.uid}");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Tampilan UI (Sama seperti main.dart yang saya berikan sebelumnya)
          SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                const SizedBox(height: 80),
                const Icon(Icons.church, size: 100, color: Colors.blue),
                const Text("GKII SILOAM", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 40),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: "Email"),
                ),
                TextField(
                  controller: _passController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "Password"),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isLoading ? null : _loginManual,
                  child: const Text("LOGIN"),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  icon: const Icon(Icons.login),
                  label: const Text("Sign in with Google"),
                ),
              ],
            ),
          ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}