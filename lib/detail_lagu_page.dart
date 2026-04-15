import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:audioplayers/audioplayers.dart'; // 👈 IMPORT AUDIO SULTAN

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

  // 👇 VARIABEL MESIN AUDIO SULTAN 👇
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _setupAudio();
  }

  // Pasang Telinga untuk Durasi dan Status Lagu
  void _setupAudio() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted) setState(() => _duration = newDuration);
    });
    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (mounted) setState(() => _position = newPosition);
    });
  }

  @override
  void dispose() {
    // 👇 SATPAM AUDIO: Wajib dimatikan saat jemaat kembali ke daftar lagu
    _audioPlayer.dispose(); 
    super.dispose();
  }

  // LOGIKA PINTAR PLAY/PAUSE VIA GITHUB STREAMING
  void _playPauseAudio() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      String rawNomor = widget.songData['nomor'] ?? "";
      // Bersihkan huruf/simbol, ambil angkanya saja
      String cleanNomor = rawNomor.replaceAll(RegExp(r'[^0-9]'), '');
      
      if (cleanNomor.isEmpty) {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Audio tidak tersedia untuk lagu ini.")));
         return;
      }

      // 👇 JALAN NINJA: PIPA STREAMING GITHUB BOS 👇
      String githubBaseUrl = "https://raw.githubusercontent.com/pulicarpus/audio-nki/main/";
      String fileName = "NKI_${cleanNomor.padLeft(3, '0')}.mp3";
      String fullUrl = githubBaseUrl + fileName;
      
      try {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Memuat audio dari server...")));
        // Menyedot lagu dari GitHub!
        await _audioPlayer.play(UrlSource(fullUrl));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Maaf, file MP3 belum tersedia di server.")));
      }
    }
  }

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
    
    // Cek apakah ini lagu NKI atau Kontemporer (Biar tombol play cuma muncul di NKI)
    bool isNKI = widget.songData['kategori']?.toString().toUpperCase() == "NKI" || nomor.isNotEmpty;

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
                crossAxisAlignment: CrossAxisAlignment.center, 
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
                  
                  // 👇 PEMUTAR AUDIO MELAYANG (MUNCUL JIKA NKI) 👇
                  if (isNKI)
                    Container(
                      margin: const EdgeInsets.only(top: 20, bottom: 5),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.indigo.shade100)
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.indigo,
                            radius: 22,
                            child: IconButton(
                              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                              onPressed: _playPauseAudio,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                trackHeight: 4,
                              ),
                              child: Slider(
                                activeColor: Colors.indigo,
                                inactiveColor: Colors.indigo.shade200,
                                min: 0,
                                max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0,
                                value: _position.inSeconds.toDouble().clamp(0.0, _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0),
                                onChanged: (value) async {
                                  if (_duration.inSeconds > 0) {
                                    final position = Duration(seconds: value.toInt());
                                    await _audioPlayer.seek(position);
                                  }
                                },
                              ),
                            ),
                          ),
                          Text(
                            "${_position.inMinutes}:${(_position.inSeconds % 60).toString().padLeft(2, '0')}",
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo),
                          ),
                          const SizedBox(width: 15),
                        ],
                      ),
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
                        textAlign: TextAlign.left, // RATA KIRI SULTAN
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