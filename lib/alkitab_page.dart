import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart'; 
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:firebase_auth/firebase_auth.dart';     
import 'package:audioplayers/audioplayers.dart'; 

import 'bible_models.dart';
import 'notes_pages.dart';
import 'search_page.dart';

class AlkitabPage extends StatefulWidget {
  const AlkitabPage({super.key});
  @override
  State<AlkitabPage> createState() => _AlkitabPageState();
}

class _AlkitabPageState extends State<AlkitabPage> {
  Database? _db;
  List<Map<String, dynamic>> _verses = [];
  Map<int, List<String>> _perikopMap = {}; 
  List<BibleBook> _allBooks = [];
  Set<int> _selectedVerses = {};
  Map<int, List<String>> _verseNotesMap = {}; 
  final ScrollController _scrollController = ScrollController();
  
  String _currentVersion = "TB.SQLite3"; 
  int _currentBookNum = 10; 
  int _currentChapter = 1;
  bool _isLoading = true;
  bool _isSyncing = false; 
  late SharedPreferences _prefs;

  double _fontSize = 18.0;
  double _baseFontSize = 18.0;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isAudioLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initApp();
    _setupAudioListeners();
  }

  void _setupAudioListeners() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _audioPlayer.onDurationChanged.listen((d) { if (mounted) setState(() => _duration = d); });
    _audioPlayer.onPositionChanged.listen((p) { if (mounted) setState(() => _position = p); });
    _audioPlayer.onPlayerComplete.listen((e) { if (mounted) setState(() { _isPlaying = false; _position = Duration.zero; }); });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 👇 LOGIKA PENEMBAK JITU KE GITHUB PRIBADI BOS 👇
  String _getAudioUrl(int bookNum, int chapter) {
    // Standard nomor kitab Wahyu di database SQLite biasanya 660
    // Rumus konversi kita: 660 / 10 = 66
    int standardBookNum = bookNum < 400 ? (bookNum ~/ 10) : (((bookNum - 470) ~/ 10) + 40);
    
    // SESUAIKAN JALUR JIKA KITAB WAHYU (Standard 66)
    if (standardBookNum == 66) {
      String chapterStr = chapter.toString().padLeft(2, '0');
      
      // Link mengarah ke folder audio di repo pulicarpus
      // Pastikan nama file di Github: 27_wah01.mp3 (sesuai screenshot Acode Bos)
      return "https://raw.githubusercontent.com/pulicarpus/gereja_mobile/master/audio/27_wah$chapterStr.mp3";
    }
    
    // Ban serep untuk kitab lain yang belum di-upload ke Github
    String bookStr = standardBookNum.toString().padLeft(2, '0');
    return "https://archive.org/download/IndonesianBibleAudio/b${bookStr}_$chapter.mp3";
  }

  Future<void> _playPauseAudio() async {
    try {
      if (_isPlaying) { 
        await _audioPlayer.pause(); 
      } else {
        setState(() => _isAudioLoading = true);
        String audioUrl = _getAudioUrl(_currentBookNum, _currentChapter);
        
        // Konfigurasi Audio Player agar tidak dianggap robot oleh server
        await _audioPlayer.setAudioContext(AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
          iOS: const AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: [
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.mixWithOthers,
            ],
          ),
        ));

        await _audioPlayer.play(UrlSource(audioUrl));
        setState(() => _isAudioLoading = false);
      }
    } catch (e) {
      setState(() => _isAudioLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Putar: ${e.toString()}")));
    }
  }

  void _resetAudio() {
    _audioPlayer.stop();
    _duration = Duration.zero;
    _position = Duration.zero;
  }

  // --- INISIALISASI DATA ---
  Future<void> _initApp() async {
    _prefs = await SharedPreferences.getInstance();
    _currentBookNum = _prefs.getInt('LAST_BOOK_NUM') ?? 10; 
    _currentChapter = _prefs.getInt('LAST_CHAPTER') ?? 1;
    _currentVersion = _prefs.getString('LAST_VERSION') ?? "TB.SQLite3"; 
    _fontSize = _prefs.getDouble('LAST_FONT_SIZE') ?? 18.0;
    await _loadDatabase();
  }

  void _saveLastPosition() {
    _prefs.setInt('LAST_BOOK_NUM', _currentBookNum);
    _prefs.setInt('LAST_CHAPTER', _currentChapter);
    _prefs.setString('LAST_VERSION', _currentVersion);
  }

  void _saveFontSize() {
    _prefs.setDouble('LAST_FONT_SIZE', _fontSize);
  }

  Future<void> _loadDatabase() async {
    setState(() => _isLoading = true);
    try {
      var dbPath = await getDatabasesPath();
      String path = p.join(dbPath, _currentVersion);
      if (!(await databaseExists(path))) {
        ByteData data = await rootBundle.load("assets/$_currentVersion");
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await File(path).writeAsBytes(bytes, flush: true);
      }
      _db = await openDatabase(path);
      final bookData = await _db!.query('books', orderBy: 'book_number ASC');
      setState(() {
        _allBooks = bookData.map((e) => BibleBook(bookNumber: e['book_number'] as int, name: e['long_name'].toString(), shortName: e['short_name'].toString())).toList();
      });
      await _loadContent();
    } catch (e) { setState(() => _isLoading = false); }
  }

  Future<void> _loadContent({int? scrollToVerse}) async {
    if (_db == null) return;
    try {
      final verseData = await _db!.query('verses', where: 'book_number = ? AND chapter = ?', whereArgs: [_currentBookNum, _currentChapter], orderBy: 'verse ASC');
      List<Map<String, dynamic>> storyData = [];
      try { storyData = await _db!.query('stories', where: 'book_number = ? AND chapter = ?', whereArgs: [_currentBookNum, _currentChapter], orderBy: 'verse ASC'); } catch (e) {}
      _perikopMap.clear();
      for (var s in storyData) {
        int vNum = s['verse'] as int;
        if (!_perikopMap.containsKey(vNum)) _perikopMap[vNum] = [];
        _perikopMap[vNum]!.add(s['title'].toString());
      }
      _verses = verseData;
      _syncNotes(); 
      setState(() { _isLoading = false; _selectedVerses.clear(); });
      
      if (scrollToVerse != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo((scrollToVerse - 1) * (_fontSize * 3.5), duration: const Duration(milliseconds: 600), curve: Curves.easeOut);
          }
        });
      }
    } catch (e) {}
  }

  void _syncNotes() {
    _verseNotesMap.clear();
    final allKeys = _prefs.getStringList("ALL_NOTE_KEYS") ?? [];
    if (_allBooks.isEmpty) return;
    String prefix = "${_allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name} $_currentChapter:";
    for (var key in allKeys) {
      String? raw = _prefs.getString(key);
      if (raw != null && raw.split("~|~")[0].startsWith(prefix)) {
        try {
          int v = int.parse(raw.split("~|~")[0].split(":")[1].split(RegExp(r'[-,]')).last);
          if (!_verseNotesMap.containsKey(v)) _verseNotesMap[v] = [];
          _verseNotesMap[v]!.add(key);
        } catch (e) {}
      }
    }
  }

  String _cleanText(String text) => text.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  // --- PEMBUAT TAMPILAN (UI) ---
  Widget _buildPerikopItem(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 25, bottom: 10), 
      child: Text(title, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: _fontSize + 2, color: Colors.indigo.shade900))
    );
  }

  @override
  Widget build(BuildContext context) {
    String bookName = _allBooks.isEmpty ? "" : _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
        title: InkWell(onTap: _showNavigation, child: Row(mainAxisSize: MainAxisSize.min, children: [Text("$bookName $_currentChapter"), const Icon(Icons.arrow_drop_down)])),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (c) => SearchPage(db: _db!, allBooks: _allBooks, currentBookNum: _currentBookNum))).then((res) {
              if (res != null) {
                setState(() { _currentBookNum = res['book_number']; _currentChapter = res['chapter']; });
                _resetAudio(); _saveLastPosition(); _loadContent(scrollToVerse: res['verse']);
              }
            });
          }),
        ],
        // PEMUTAR AUDIO DI HEADER
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(45),
          child: Container(
            color: Colors.indigo[800], 
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                IconButton(
                  icon: _isAudioLoading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.orange, size: 30), 
                  onPressed: _playPauseAudio,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: Colors.orange, inactiveTrackColor: Colors.white30, thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: _position.inSeconds.toDouble(), 
                      max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0, 
                      onChanged: (v) => _audioPlayer.seek(Duration(seconds: v.toInt()))
                    ),
                  )
                ),
                IconButton(
                  icon: const Icon(Icons.stop_circle, color: Colors.redAccent, size: 28), 
                  onPressed: _resetAudio,
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : GestureDetector(
        onScaleStart: (d) => _baseFontSize = _fontSize,
        onScaleUpdate: (d) => setState(() => _fontSize = (_baseFontSize * d.scale).clamp(12.0, 40.0)),
        onScaleEnd: (d) => _saveFontSize(),
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(15),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _buildChapterContent()),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildChapterContent() {
    List<Widget> content = [];
    for (var v in _verses) {
      int vNum = v['verse'] as int;
      if (_perikopMap.containsKey(vNum)) {
        for (var title in _perikopMap[vNum]!) { content.add(_buildPerikopItem(title)); }
      }
      content.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: RichText(text: TextSpan(style: TextStyle(color: Colors.black87, fontSize: _fontSize, height: 1.6), children: [
            TextSpan(text: "$vNum. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
            TextSpan(text: _cleanText(v['text'])),
          ])),
        )
      );
    }
    return content;
  }

  void _showNavigation() {
    showGeneralDialog(
      context: context, barrierDismissible: true, barrierLabel: "Nav", barrierColor: Colors.black54,
      pageBuilder: (context, a1, a2) => Align(
        alignment: Alignment.topCenter,
        child: Material(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(25)),
          child: _NavSheet(
            allBooks: _allBooks, db: _db!,
            onSelectionComplete: (b, c, v) { 
              setState(() { _currentBookNum = b; _currentChapter = c; }); 
              _resetAudio(); _saveLastPosition(); _loadContent(scrollToVerse: v); 
            },
          ),
        ),
      ),
    );
  }
}

// --- CLASS NAVIGASI ---
class _NavSheet extends StatefulWidget {
  final List<BibleBook> allBooks; final Database db; final Function(int, int, int) onSelectionComplete;
  const _NavSheet({required this.allBooks, required this.db, required this.onSelectionComplete});
  @override State<_NavSheet> createState() => _NavSheetState();
}
class _NavSheetState extends State<_NavSheet> {
  BibleBook? selBook; int? selChapter; List<int> chapters = []; List<int> verses = [];
  void _getChapters(BibleBook b) async {
    final res = await widget.db.rawQuery("SELECT DISTINCT chapter FROM verses WHERE book_number = ? ORDER BY chapter ASC", [b.bookNumber]);
    setState(() { selBook = b; chapters = res.map((e) => e['chapter'] as int).toList(); selChapter = null; });
  }
  void _getVerses(int c) async {
    final res = await widget.db.rawQuery("SELECT verse FROM verses WHERE book_number = ? AND chapter = ? ORDER BY verse ASC", [selBook!.bookNumber, c]);
    setState(() { selChapter = c; verses = res.map((e) => e['verse'] as int).toList(); });
  }
  @override 
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      AppBar(title: Text(selBook == null ? "Pilih Kitab" : (selChapter == null ? selBook!.name : "${selBook!.name} $selChapter")), leading: selBook != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => selChapter != null ? selChapter = null : selBook = null)) : null),
      Expanded(child: _buildGrid()),
    ]),
  );

  Widget _buildGrid() {
    if (selChapter != null) return GridView.builder(padding: const EdgeInsets.all(10), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 60), itemCount: verses.length, itemBuilder: (c, i) => InkWell(onTap: () => widget.onSelectionComplete(selBook!.bookNumber, selChapter!, verses[i]), child: Center(child: Text("${verses[i]}"))));
    if (selBook != null) return GridView.builder(padding: const EdgeInsets.all(10), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 60), itemCount: chapters.length, itemBuilder: (c, i) => InkWell(onTap: () => _getVerses(chapters[i]), child: Center(child: Text("${chapters[i]}"))));
    return ListView.builder(itemCount: widget.allBooks.length, itemBuilder: (c, i) => ListTile(title: Text(widget.allBooks[i].name), onTap: () => _getChapters(widget.allBooks[i])));
  }
}