import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'user_manager.dart';

// 👇 IMPORT HALAMAN VALIDASI GEREJA 👇
import 'validasi_gereja_page.dart';

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

  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
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
        OneSignal.login(user.uid);
        _checkUserRegistration(user);
      }
    } catch (e) {
      _showToast("Google Sign-In Gagal: $e");
      setState(() => _isLoading = false);
    }
  }

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
      if (userCredential.user != null) {
        OneSignal.login(userCredential.user!.uid);
        _checkUserRegistration(userCredential.user!);
      }
    } catch (e) {
      _showToast("Login Manual Gagal: $e");
      setState(() => _isLoading = false);
    }
  }

  void _checkUserRegistration(User user) async {
    try {
      DocumentSnapshot doc = await _db.collection("users").doc(user.uid).get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        String role = data['role'] ?? "user";
        String? churchId = data['churchId']; // Sengaja tanpa default biar ketahuan kalau kosong
        String churchName = data['churchName'] ?? "";
        String nama = data['namaLengkap'] ?? user.displayName ?? "Jemaat";
        String? foto = data['photoUrl'] ?? user.photoURL;

        // 👇 SATPAM CEGATAN 👇
        // Kalau dia user lama tapi belum punya gereja (atau gerejanya string kosong), TENDANG ke validasi!
        if (role != "superadmin" && (churchId == null || churchId.trim().isEmpty)) {
          _goToValidasiManual(user);
          return; // Stop proses masuk ke Main Activity
        }

        // MENGGUNAKAN LOGIKA BOS: setUser
        await UserManager().setUser(
          role: role,
          churchId: churchId ?? "",
          churchName: churchName,
          uId: user.uid,
          uNama: nama,
          uFoto: foto,
          uKomisi: data['kelompok'] ?? "Umum",
        );

        // Jika Superadmin, beri Tag khusus di OneSignal
        if (role == "superadmin") {
          OneSignal.User.addTagWithKey("active_church", "SUPERADMIN");
        } else if (churchId != null && churchId.isNotEmpty) {
          OneSignal.User.addTagWithKey("active_church", churchId);
        }

        _goToMainActivity();
      } else {
        _saveNewUserAndValidate(user);
      }
    } catch (e) {
      debugPrint("Error checkUser: $e");
      _goToValidasiManual(user);
    }
  }

  void _saveNewUserAndValidate(User user) async {
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
      await _db.collection("users").doc(user.uid).set(newUser, SetOptions(merge: true));
      _goToValidasiManual(user);
    } catch (e) {
      _goToValidasiManual(user);
    }
  }

  void _goToValidasiManual(User user) {
    setState(() => _isLoading = false);
    _showToast("Silakan masukkan kode undangan gereja Anda.");
    
    // 👇 NAVIGASI YANG BENAR DENGAN MEMBAWA KOPER DATA 👇
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
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(30),
            child: Column(
              children: [
                const SizedBox(height: 80),
                const Icon(Icons.church, size: 80, color: Colors.indigo),
                const SizedBox(height: 40),
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
                  child: ElevatedButton(onPressed: _loginManual, child: const Text("LOGIN")),
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text("Atau")),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _signInWithGoogle,
                    icon: const Icon(Icons.g_mobiledata, size: 30),
                    label: const Text("Masuk dengan Google"),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}