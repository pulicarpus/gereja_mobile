import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DetailLaguPage extends StatefulWidget {
  final List<Map<String, dynamic>> songList;
  final int initialIndex;

  const DetailLaguPage({
    super.key,
    required this.songList,
    required this.initialIndex,
  });

  @override
  State<DetailLaguPage> createState() => _DetailLaguPageState();
}

class _DetailLaguPageState extends State<DetailLaguPage> {
  double _fontSize = 20.0;

  late PageController _pageController;
  late int _currentIndex;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _loadedAudioUrl;

  @override
  void initState() {
    super.initState();
    final maxIndex = widget.songList.isEmpty ? 0 : widget.songList.length - 1;
    _currentIndex = widget.initialIndex.clamp(0, maxIndex).toInt();
    _pageController = PageController(initialPage: _currentIndex);
    _loadFontPreference();
    _setupAudio();
  }

  String _text(dynamic raw, [String fallback = ""]) {
    final value = raw?.toString().trim();
    return (value == null || value.isEmpty) ? fallback : value;
  }

  String _category(Map<String, dynamic> song) {
    final value = _text(song['kategori']).toUpperCase();
    if (value.isEmpty || value == "HYMNE") return "NKI";
    return value;
  }

  bool _isNki(Map<String, dynamic> song) => _category(song) == "NKI";

  String? _audioUrlForSong(Map<String, dynamic> song) {
    if (!_isNki(song)) return null;
    final rawNomor = _text(song['nomor']);
    final cleanNomor = rawNomor.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanNomor.isEmpty) return null;
    final fileName = "NKI_${cleanNomor.padLeft(3, '0')}.mp3";
    return "https://raw.githubusercontent.com/pulicarpus/audio-nki/main/$fileName";
  }

  Future<void> _loadFontPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble("song_lyrics_font_size");
    if (!mounted || saved == null) return;
    setState(() {
      _fontSize = saved.clamp(14.0, 40.0).toDouble();
    });
  }

  Future<void> _saveFontPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble("song_lyrics_font_size", _fontSize);
  }

  void _setupAudio() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });
    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted) setState(() => _duration = newDuration);
    });
    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (mounted) setState(() => _position = newPosition);
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
          _duration = Duration.zero;
          _loadedAudioUrl = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _onPageChanged(int index) async {
    await _audioPlayer.stop();
    if (!mounted) return;
    setState(() {
      _currentIndex = index;
      _isPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _loadedAudioUrl = null;
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _playPauseAudio() async {
    if (widget.songList.isEmpty) return;

    final currentSong = widget.songList[_currentIndex];
    final url = _audioUrlForSong(currentSong);
    if (url == null) {
      _showSnack("Audio tidak tersedia untuk lagu ini.");
      return;
    }

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
        return;
      }

      final canResume = _loadedAudioUrl == url &&
          _position > Duration.zero &&
          (_duration == Duration.zero || _position < _duration);

      if (canResume) {
        await _audioPlayer.resume();
        return;
      }

      if (_position == Duration.zero) {
        _showSnack("Memuat audio NKI...");
      }
      await _audioPlayer.play(UrlSource(url));
      if (mounted) {
        setState(() => _loadedAudioUrl = url);
      }
    } catch (e) {
      debugPrint("Audio NKI gagal: $e");
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _loadedAudioUrl = null;
        });
      }
      _showSnack("File MP3 belum tersedia atau gagal dimuat.");
    }
  }

  void _zoomIn() {
    setState(() {
      _fontSize = (_fontSize + 2.0).clamp(14.0, 40.0).toDouble();
    });
    _saveFontPreference();
  }

  void _zoomOut() {
    setState(() {
      _fontSize = (_fontSize - 2.0).clamp(14.0, 40.0).toDouble();
    });
    _saveFontPreference();
  }

  @override
  Widget build(BuildContext context) {
    const mainBgColor = Color(0xFFEFE6D6);
    const paperColor = Color(0xFFFCFBF4);
    const headerIndigo = Color(0xFF1A237E);

    if (widget.songList.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Lirik Lagu"),
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text("Data lagu tidak tersedia.")),
      );
    }

    final currentSong = widget.songList[_currentIndex];
    final judul = _text(currentSong['judul'], "Tanpa Judul");
    final nomor = _text(currentSong['nomor']);
    final pencipta = _text(currentSong['pencipta'], "Pelayan Tuhan");
    final lirik = _text(currentSong['lirik'], "Lirik tidak tersedia.");
    final isNKI = _isNki(currentSong);
    final hasAudioNumber = _audioUrlForSong(currentSong) != null;

    final maxSeconds = _duration.inSeconds > 0
        ? _duration.inSeconds.toDouble()
        : 1.0;
    final currentSeconds =
        _position.inSeconds.toDouble().clamp(0.0, maxSeconds).toDouble();

    return Scaffold(
      backgroundColor: mainBgColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Lirik Lagu",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            if (isNKI)
              Text(
                "Lagu ${nomor.isNotEmpty ? nomor : '-'}",
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (isNKI && hasAudioNumber)
            IconButton(
              tooltip: _isPlaying ? "Jeda audio" : "Putar audio NKI",
              icon: Icon(
                _isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                size: 32,
                color: Colors.orangeAccent,
              ),
              onPressed: _playPauseAudio,
            ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              Share.share(
                "*$judul*\n$pencipta\n\n$lirik",
                subject: "Lirik: $judul",
              );
            },
          )
        ],
        bottom: isNKI && hasAudioNumber
            ? PreferredSize(
                preferredSize: const Size.fromHeight(15),
                child: Container(
                  color: Colors.indigo.shade800,
                  height: 15,
                  child: SliderTheme(
                    data: const SliderThemeData(
                      trackHeight: 2,
                      thumbShape:
                          RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape:
                          RoundSliderOverlayShape(overlayRadius: 10),
                    ),
                    child: Slider(
                      activeColor: Colors.orangeAccent,
                      inactiveColor: Colors.indigo.shade300,
                      min: 0,
                      max: maxSeconds,
                      value: currentSeconds,
                      onChanged: _duration.inSeconds > 0
                          ? (value) async {
                              await _audioPlayer.seek(
                                Duration(seconds: value.toInt()),
                              );
                            }
                          : null,
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        itemCount: widget.songList.length,
        itemBuilder: (context, index) {
          final song = widget.songList[index];
          final itemJudul = _text(song['judul'], "Tanpa Judul");
          final itemNomor = _text(song['nomor']);
          final itemLirik =
              _text(song['lirik'], "Lirik tidak tersedia.");
          final itemPencipta =
              _text(song['pencipta'], "Pelayan Tuhan");

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
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
                        offset: const Offset(0, 5),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        itemNomor.isNotEmpty
                            ? "$itemNomor. $itemJudul"
                            : itemJudul,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: headerIndigo,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        itemPencipta,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const Divider(height: 40, thickness: 1.2),
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          itemLirik,
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            fontSize: _fontSize,
                            height: 1.6,
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.swipe_left,
                      color: Colors.grey[400],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Geser untuk pindah lagu",
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.swipe_right,
                      color: Colors.grey[400],
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: "btnZoomIn",
            backgroundColor: Colors.white,
            foregroundColor: Colors.indigo[900],
            elevation: 4,
            onPressed: _zoomIn,
            child: const Icon(Icons.zoom_in),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.small(
            heroTag: "btnZoomOut",
            backgroundColor: Colors.white,
            foregroundColor: Colors.indigo[900],
            elevation: 4,
            onPressed: _zoomOut,
            child: const Icon(Icons.zoom_out),
          ),
        ],
      ),
    );
  }
}
