import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import untuk ngecek login

// Sesuaikan import ini dengan nama file Bos
import 'main.dart'; 
import 'login_page.dart'; 

class VideoSplashPage extends StatefulWidget {
  const VideoSplashPage({super.key});

  @override
  State<VideoSplashPage> createState() => _VideoSplashPageState();
}

class _VideoSplashPageState extends State<VideoSplashPage> {
  late VideoPlayerController _controller;
  bool _isNavigating = false; // Mencegah pindah halaman berkali-kali

  @override
  void initState() {
    super.initState();
    // Pastikan jalurnya sesuai dengan video polosan Bos
    _controller = VideoPlayerController.asset("assets/videos/splash_video.mp4")
      ..initialize().then((_) {
        _controller.setVolume(0.0); // SATPAM AUDIO: Mute suara videonya
        setState(() {});
        _controller.play(); 
      });

    // Pasang telinga untuk ngecek kapan videonya selesai
    _controller.addListener(() {
      if (_controller.value.isInitialized && 
          _controller.value.position >= _controller.value.duration && 
          !_isNavigating) {
            
        _isNavigating = true; // Kunci supaya tidak pindah halaman dobel
        _checkAuthAndNavigate();
      }
    });
  }

  void _checkAuthAndNavigate() {
    // Cek apakah jemaat sudah login atau belum
    Widget nextPage = FirebaseAuth.instance.currentUser == null 
        ? const LoginPage() 
        : const MainActivity();

    // Lakukan lompatan
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => nextPage),
    );
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
          // LAYER 1 (PALING BAWAH): VIDEO OMBAK FULL SCREEN
          // ==========================================
          Center(
            child: _controller.value.isInitialized
                ? SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    // 👇 INI DIA KUNCI SULTANNYA: UBAH JADI COVER 👇
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
          // LAYER 2 (PALING ATAS): TEKS TAJAM (HD)
          // ==========================================
          if (_controller.value.isInitialized)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).size.height * 0.35, // Ketinggian teks (35% dari bawah)
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Selamat Datang di",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900, // Warna biru tua
                      shadows: [
                        Shadow(color: Colors.white.withOpacity(0.8), blurRadius: 10, offset: const Offset(0, 2))
                      ]
                    ),
                  ),
                  const SizedBox(height: 5), // Jarak baris
                  Text(
                    "GKII Mobile",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 38, // Ukuran gagah
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