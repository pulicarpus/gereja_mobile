import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:audioplayers/audioplayers.dart'; 

class DetailLaguPage extends StatefulWidget {
  // 👇 SEKARANG MENERIMA SELURUH DAFTAR LAGU 👇
  final List<Map<String, dynamic>> songList;
  final int initialIndex;

  const DetailLaguPage({super.key, required this.songList, required this.initialIndex});

  @override
  State<DetailLaguPage> createState() => _DetailLaguPageState();
}

class _DetailLaguPageState extends State<DetailLaguPage> {
  double _fontSize = 20.0; 
  double _baseFontSize = 20.0;

  // 👇 VARIABEL UNTUK FITUR SWIPE 👇
  late PageController _pageController;
  late int _currentIndex;

  // VARIABEL MESIN AUDIO SULTAN
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _setupAudio();
  }

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
    _audioPlayer.dispose(); 
    _pageController.dispose();
    super.dispose();
  }

  // 👇 FUNGSI SAAT JEMAAT MENGGESER LAYAR 👇
  void _onPageChanged(int index) async {
    await _audioPlayer.stop(); // Matikan lagu sebelumnya
    setState(() {
      _currentIndex = index;
      _isPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
  }

  void _playPauseAudio() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      // Ambil lagu yang SEDANG TAMPIL di layar saat ini
      Map<String, dynamic> currentSong = widget.songList[_currentIndex];
      String rawNomor = currentSong['nomor'] ?? "";
      String cleanNomor = rawNomor.replaceAll(RegExp(r'[^0-9]'), '');
      
      if (cleanNomor.isEmpty) {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Audio tidak tersedia untuk lagu ini.")));
         return;
      }

      String githubBaseUrl = "https://raw.githubusercontent.com/pulicarpus/audio-nki/main/";
      String fileName = "NKI_${cleanNomor.padLeft(3, '0')}.mp3";
      String fullUrl = githubBaseUrl + fileName;
      
      try {
        if (mounted && _position == Duration.zero) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Memuat audio dari server...")));
        }
        await _audioPlayer.play(UrlSource(fullUrl));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Maaf, file MP3 belum tersedia di server.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color mainBgColor = Color(0xFFEFE6D6); 
    const Color paperColor = Color(0xFFFCFBF4); 
    const Color headerIndigo = Color(0xFF1A237E);

    // Ambil data lagu sesuai halaman yang sedang dibuka
    Map<String, dynamic> currentSong = widget.songList[_currentIndex];
    final String judul = currentSong['judul'] ?? "Tanpa Judul";
    final String nomor = currentSong['nomor'] ?? "";
    final String pencipta = currentSong['pencipta'] ?? "Pelayan Tuhan";
    final String lirik = currentSong['lirik'] ?? "Lirik tidak tersedia.";
    
    bool isNKI = currentSong['kategori']?.toString().toUpperCase() == "NKI" || nomor.isNotEmpty;

    return Scaffold(
      backgroundColor: mainBgColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Lirik Lagu", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            // Tambahan indikator kecil di bawah judul AppBar
            if (isNKI) Text("Lagu ${nomor.isNotEmpty ? nomor : '-'}", style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // 👇 TOMBOL PLAY SULTAN PINDAH KE SINI 👇
          if (isNKI)
            IconButton(
              icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 32, color: Colors.orangeAccent),
              onPressed: _playPauseAudio,
            ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              Share.share("*$judul*\n$pencipta\n\n$lirik", subject: "Lirik: $judul");
            },
          )
        ],
        // 👇 SLIDER DURASI NYELIP CANTIK DI BAWAH APPBAR 👇
        bottom: isNKI ? PreferredSize(
          preferredSize: const Size.fromHeight(15),
          child: Container(
            color: Colors.indigo.shade800,
            height: 15,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                activeColor: Colors.orangeAccent,
                inactiveColor: Colors.indigo.shade300,
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
        ) : null,
      ),
      // 👇 INI DIA MESIN GESER HALAMANNYA (PAGE VIEW) 👇
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        itemCount: widget.songList.length,
        itemBuilder: (context, index) {
          // Ambil data lagu untuk halaman yang sedang di-render
          Map<String, dynamic> song = widget.songList[index];
          final String itemJudul = song['judul'] ?? "Tanpa Judul";
          final String itemNomor = song['nomor'] ?? "";
          final String itemLirik = song['lirik'] ?? "Lirik tidak tersedia.";
          final String itemPencipta = song['pencipta'] ?? "Pelayan Tuhan";

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: paperColor,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
                    ]
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center, 
                    children: [
                      Text(
                        itemNomor.isNotEmpty ? "$itemNomor. $itemJudul" : itemJudul,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: headerIndigo),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        itemPencipta,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600], fontStyle: FontStyle.italic),
                      ),
                      const Divider(height: 40, thickness: 1.2),

                      GestureDetector(
                        onScaleStart: (details) => _baseFontSize = _fontSize,
                        onScaleUpdate: (details) {
                          setState(() {
                            _fontSize = (_baseFontSize * details.scale).clamp(14.0, 40.0);
                          });
                        },
                        child: Container(
                          color: Colors.transparent, 
                          width: double.infinity,
                          child: Text(
                            itemLirik,
                            textAlign: TextAlign.left, 
                            style: TextStyle(
                              fontSize: _fontSize,
                              height: 1.6, 
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
                
                // 👇 PETUNJUK GESER ESTETIK 👇
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.swipe_left, color: Colors.grey[400], size: 20),
                    const SizedBox(width: 8),
                    Text("Geser untuk pindah lagu", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    const SizedBox(width: 8),
                    Icon(Icons.swipe_right, color: Colors.grey[400], size: 20),
                  ],
                ),
                const SizedBox(height: 50),
              ],
            ),
          );
        },
      ),
    );
  }
}