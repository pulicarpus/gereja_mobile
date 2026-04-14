import 'package:flutter/material.dart';

class LoadingSultan extends StatefulWidget {
  final double size;
  
  // Bos bisa atur ukurannya nanti waktu memanggil widget ini
  const LoadingSultan({super.key, this.size = 60.0});

  @override
  State<LoadingSultan> createState() => _LoadingSultanState();
}

class _LoadingSultanState extends State<LoadingSultan> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    
    // Mesin penggerak animasi (berdurasi 1 detik, lalu mengulang mundur/maju)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true); // repeat(reverse: true) ini yang bikin efek "bernapas"

    // Animasi membesar-mengecil (dari 80% ke 110%)
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Animasi terang-gelap (dari agak transparan ke solid)
    _opacityAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose(); // Wajib dihapus agar memori HP tidak bocor
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(
              opacity: _opacityAnimation.value,
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // 👇 INI EFEK CAHAYA GLOWING-NYA BOS 👇
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF075E54).withOpacity(_opacityAnimation.value * 0.6),
                      blurRadius: 20,
                      spreadRadius: 5,
                    )
                  ]
                ),
                // 👇 SEMENTARA PAKAI ICON GEREJA 👇
                // Nanti kalau Bos sudah punya file gambar logo, 
                // hapus baris Icon(...) di bawah ini, lalu aktifkan baris Image.asset(...)
                
                //child: Icon(Icons.church, size: widget.size, color: const Color(0xFF075E54)),
                
                 child: Image.asset('assets/icon.png', width: widget.size, height: widget.size),
              ),
            ),
          );
        },
      ),
    );
  }
}