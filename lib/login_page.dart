import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'user_manager.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  // KONFIGURASI GOOGLE SIGN IN
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // 1. FUNGSI LOGIN GOOGLE
  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      // Sign out dulu agar bisa pilih akun lain jika mau
      await _googleSignIn.signOut();
      
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
        // SINKRONISASI 1: OneSignal Login
        OneSignal.login(user.uid);
        _checkUserRegistration(user);
      }
    } catch (e) {
      _showToast("Google Sign-In Gagal: $e");
      setState(() => _isLoading = false);
    }
  }

  // 2. FUNGSI LOGIN MANUAL (EMAIL/PASS)
  Future<void> _loginManual() async {
    final email = _emailController.text.trim();
    final pass = _passwordController.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      _showToast("Email dan Password harus diisi");
      return;
    }

    setState(() => _isLoading = true);
    try {
      final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email, 
        password: pass
      );
      final User? user = userCredential.user;

      if (user != null) {
        // SINKRONISASI 1: OneSignal Login
        OneSignal.login(user.uid);
        _checkUserRegistration(user);
      }
    } catch (e) {
      _showToast("Login Manual Gagal: $e");
      setState(() => _isLoading = false);
    }
  }

  // 3. CEK REGISTRASI USER DI FIRESTORE
  void _checkUserRegistration(User user) async {
    try {
      DocumentSnapshot doc = await _db.collection("users").doc(user.uid).get();

      if (doc.exists) {
        String? churchId = doc.get("churchId");
        
        if (churchId != null && churchId.isNotEmpty) {
          // USER SUDAH TERVALIDASI
          String role = doc.get("role") ?? "user";
          String cName = doc.get("churchName") ?? "";
          String nama = doc.get("namaLengkap") ?? user.displayName ?? "";

          // SINKRONISASI 2: OneSignal Tag
          OneSignal.User.addTagWithKey("active_church", churchId);

          // Simpan ke Session Lokal
          await UserManager().saveSession(
            uid: user.uid,
            role: role,
            churchId: churchId,
            churchName: cName,
            userName: nama,
            photoUrl: user.photoUrl?.toString() ?? ""
          );

          _goToMainActivity();
        } else {
          // CHURCH ID KOSONG -> VALIDASI MANUAL
          _goToValidasiManual(user);
        }
      } else {
        // USER BARU -> SIMPAN DAN VALIDASI
        _saveNewUserAndValidate(user);
      }
    } catch (e) {
      _goToValidasiManual(user);
    }
  }

  // 4. SIMPAN USER BARU
  void _saveNewUserAndValidate(User user) async {
    final newUser = {
      "uid": user.uid,
      "email": user.email,
      "namaLengkap": user.displayName,
      "photoUrl": user.photoUrl?.toString(),
      "role": "user",
      "isBlocked": false,
      "churchId": "",
      "churchName": ""
    };

    try {
      await _db.collection("users").doc(user.uid).set(newUser, SetOptions(merge: true));
      _goToValidasiManual(user);
    } catch (e) {
      _goToValidasiManual(user);
    }
  }

  void _goToValidasiManual(User user) {
    setState(() => _isLoading = false);
    // Navigasi ke halaman Validasi Gereja (buat file-nya nanti)
    _showToast("Menuju Validasi Gereja...");
    // Navigator.pushReplacementNamed(context, '/validasi');
  }

  void _goToMainActivity() {
    setState(() => _isLoading = false);
    Navigator.pushReplacementNamed(context, '/home');
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(30),
            child: Column(
              children: [
                const SizedBox(height: 80),
                const Icon(Icons.church, size: 100, color: Colors.indigo),
                const SizedBox(height: 20),
                const Text("GKII SILOAM", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 40),
                
                // Form Login Manual
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loginManual,
                    child: const Text("LOGIN"),
                  ),
                ),
                
                const SizedBox(height: 20),
                const Text("Atau"),
                const SizedBox(height: 20),

                // Button Google Sign In
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _signInWithGoogle,
                    icon: Image.network('https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_Logo.png', height: 20),
                    label: const Text("Masuk dengan Google"),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}