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
    _controller = VideoPlayerController.asset("assets/videos/splash_video.mp4")
      ..initialize().then((_) {
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
      body: Center(
        child: _controller.value.isInitialized
            ? SizedBox.expand( // Memaksa video agar memenuhi layar
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
    );
  }
}