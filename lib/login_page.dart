import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'user_manager.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isLoading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await _auth.signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        // PERBAIKAN: Gunakan .doc() bukan .document()
        DocumentSnapshot doc = await _db.collection("users").doc(user.uid).get();

        if (!doc.exists) {
          await _registerNewUser(user);
        }

        await UserManager().saveToPrefsWithId(user.uid);
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login Gagal: $e")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _registerNewUser(User user) async {
    Map<String, dynamic> newUser = {
      "uid": user.uid,
      "nama": user.displayName ?? "Jemaat",
      "email": user.email,
      "fotoUrl": user.photoURL,
      "role": "jemaat",
      "churchId": "default_church_id", // Sesuaikan dengan ID Gereja Bos
      "createdAt": FieldValue.serverTimestamp(),
    };
    
    // PERBAIKAN: Gunakan .doc() bukan .document()
    await _db.collection("users").doc(user.uid).set(newUser, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _isLoading 
          ? const CircularProgressIndicator() 
          : ElevatedButton.icon(
              icon: const Icon(Icons.login),
              label: const Text("Masuk dengan Google"),
              onPressed: _handleGoogleSignIn,
            ),
      ),
    );
  }
}