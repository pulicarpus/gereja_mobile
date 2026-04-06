import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class DetailLaguPage extends StatefulWidget {
  final Map<String, dynamic> songData;

  const DetailLaguPage({super.key, required this.songData});

  @override
  State<DetailLaguPage> createState() => _DetailLaguPageState();
}

class _DetailLaguPageState extends State<DetailLaguPage> {
  // Variabel untuk Zoom Huruf
  double _fontSize = 20.0; 
  double _baseFontSize = 20.0;

  @override
  Widget build(BuildContext context) {
    // Tema warna "Warm Paper" agar jemaat nyaman baca di gereja
    const Color mainBgColor = Color(0xFFEFE6D6); 
    const Color paperColor = Color(0xFFFCFBF4); 
    const Color headerIndigo = Color(0xFF1A237E);

    final String judul = widget.songData['judul'] ?? "Tanpa Judul";
    final String nomor = widget.songData['nomor'] ?? "";
    final String lirik = widget.songData['lirik'] ?? "Lirik tidak tersedia.";
    final String pencipta = widget.songData['pencipta'] ?? "Pelayan Tuhan";

    return Scaffold(
      backgroundColor: mainBgColor,
      appBar: AppBar(
        title: const Text("Lirik Lagu", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              Share.share("*$judul*\n$pencipta\n\n$lirik", subject: "Lirik: $judul");
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // KARTU LIRIK
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: paperColor,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5)
                  )
                ]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center, // Lirik biasanya rata tengah bos
                children: [
                  // JUDUL & NOMOR
                  Text(
                    nomor.isNotEmpty ? "$nomor. $judul" : judul,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24, 
                      fontWeight: FontWeight.bold, 
                      color: headerIndigo
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pencipta,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600], fontStyle: FontStyle.italic),
                  ),
                  const Divider(height: 40, thickness: 1.2),

                  // AREA LIRIK DENGAN PINCH TO ZOOM
                  GestureDetector(
                    onScaleStart: (details) {
                      _baseFontSize = _fontSize;
                    },
                    onScaleUpdate: (details) {
                      setState(() {
                        // Batasi zoom minimal 14, maksimal 40
                        _fontSize = (_baseFontSize * details.scale).clamp(14.0, 40.0);
                      });
                    },
                    child: Container(
                      color: Colors.transparent, // Penting agar deteksi sentuhan luas
                      width: double.infinity,
                      child: Text(
                        lirik,
                        textAlign: TextAlign.center, // Rata tengah biar kayak buku lagu sungguhan
                        style: TextStyle(
                          fontSize: _fontSize,
                          height: 1.6, // Spasi baris agar tidak tumpang tindih
                          color: Colors.black87,
                          fontWeight: FontWeight.w500
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Text(
              "Gunakan dua jari (pinch) untuk memperbesar huruf",
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}