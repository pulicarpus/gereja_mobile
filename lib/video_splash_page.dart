import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_auth/firebase_auth.dart'; 

import 'main.dart'; 
import 'login_page.dart'; 
import 'user_manager.dart'; // 👈 IMPORT OTAK MEMORI KITA

// 👇 IMPORT 2 GERBANG TOL KITA 👇
import 'validasi_gereja_page.dart';
import 'sinkronisasi_jemaat_page.dart';

class VideoSplashPage extends StatefulWidget {
  const VideoSplashPage({super.key});

  @override
  State<VideoSplashPage> createState() => _VideoSplashPageState();
}

class _VideoSplashPageState extends State<VideoSplashPage> {
  late VideoPlayerController _controller;
  bool _isNavigating = false; 

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset("assets/videos/splash_video.mp4")
      ..initialize().then((_) {
        _controller.setVolume(0.0); 
        setState(() {});
        _controller.play(); 
      });

    _controller.addListener(() {
      if (_controller.value.isInitialized && 
          _controller.value.position >= _controller.value.duration && 
          !_isNavigating) {
            
        _isNavigating = true; 
        _checkAuthAndNavigate();
      }
    });
  }

  // 👇 LOGIKA SATPAM SULTAN DIPASANG DI SINI 👇
  Future<void> _checkAuthAndNavigate() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // 1. Belum Login sama sekali
      _doNavigate(const LoginPage());
      return;
    }

    // 2. Load memori dari HP (Apakah dia sudah sinkron sebelumnya?)
    final userManager = UserManager();
    await userManager.loadFromPrefs(); 

    String? churchId = userManager.getChurchIdForCurrentView();
    String? jemaatId = userManager.jemaatId;
    String? role = userManager.userRole;

    Widget nextPage;

    if (role == "superadmin") {
      // 👑 Superadmin bebas hambatan
      nextPage = const MainActivity();
    } else if (churchId == null || churchId.trim().isEmpty) {
      // 🚩 JALUR 1: Sudah login, tapi belum masukkan kode gereja
      nextPage = ValidasiGerejaPage(
        userUid: user.uid,
        userName: user.displayName ?? "Jemaat Baru",
        userEmail: user.email ?? "",
      );
    } else if (jemaatId == null || jemaatId.trim().isEmpty) {
      // 🚩 JALUR 2: Sudah masuk gereja, tapi belum sinkron biodata
      nextPage = const SinkronisasiJemaatPage();
    } else {
      // 🚀 JALUR SULTAN: Lengkap! Langsung ke Beranda
      nextPage = const MainActivity();
    }

    _doNavigate(nextPage);
  }

  void _doNavigate(Widget page) {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => page),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ==========================================
          // LAYER 1: VIDEO OMBAK FULL SCREEN
          // ==========================================
          Center(
            child: _controller.value.isInitialized
                ? SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.cover, 
                      child: SizedBox(
                        width: _controller.value.size.width,
                        height: _controller.value.size.height,
                        child: VideoPlayer(_controller),
                      ),
                    ),
                  )
                : const CircularProgressIndicator(color: Colors.indigo), 
          ),

          // ==========================================
          // LAYER 2: TEKS TAJAM (HD)
          // ==========================================
          if (_controller.value.isInitialized)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).size.height * 0.35, 
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Selamat Datang di",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900, 
                      shadows: [
                        Shadow(color: Colors.white.withOpacity(0.8), blurRadius: 10, offset: const Offset(0, 2))
                      ]
                    ),
                  ),
                  const SizedBox(height: 5), 
                  Text(
                    "GKII Mobile",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 38, 
                      fontWeight: FontWeight.w900, 
                      color: Colors.blue.shade700,
                      shadows: [
                        Shadow(color: Colors.white.withOpacity(0.8), blurRadius: 10, offset: const Offset(0, 2))
                      ]
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}