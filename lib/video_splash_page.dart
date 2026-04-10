import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'main.dart'; // Sesuaikan dengan file utama Bos

class VideoSplashPage extends StatefulWidget {
  const VideoSplashPage({super.key});

  @override
  State<VideoSplashPage> createState() => _VideoSplashPageState();
}

class _VideoSplashPageState extends State<VideoSplashPage> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset("assets/videos/splash_video.mp4")
      ..initialize().then((_) {
        setState(() {});
        _controller.play(); // Putar video otomatis
      });

    // 👇 LOGIKA PINDAH HALAMAN SETELAH VIDEO SELESAI 👇
    _controller.addListener(() {
      if (_controller.value.position >= _controller.value.duration) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainActivity()), // Ganti ke halaman utama Bos
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Sesuaikan dengan warna video
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(), // Loading sebentar saat inisialisasi
      ),
    );
  }
}