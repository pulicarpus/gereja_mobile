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

  // 👇 KAMUS SINGKATAN SABDA UNTUK JALUR AUDIO DRAMA 👇
  final List<String> _sabdaCodes = [
    "", "kej", "kel", "ima", "bil", "ula", "yos", "hak", "rut", "1sa", "2sa",
    "1ra", "2ra", "1ta", "2ta", "ezr", "neh", "est", "ayb", "mzm", "ams",
    "pkh", "kid", "yes", "yer", "rat", "yeh", "dan", "hos", "yoe", "amo",
    "oba", "yun", "mik", "nah", "hab", "zef", "hag", "zak", "mal",
    "mat", "mrk", "luk", "yoh", "kis", "rom", "1ko", "2ko", "gal", "efe",
    "flp", "kol", "1te", "2te", "1ti", "2ti", "tit", "flm", "ibr", "yak",
    "1pe", "2pe", "1yo", "2yo", "3yo", "yud", "why"
  ];

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

  // --- LOGIKA AUDIO SABDA ---
  String _getAudioUrl(int bookNum, int chapter) {
    int standardBookNum = bookNum < 400 ? (bookNum ~/ 10) : (((bookNum - 470) ~/ 10) + 40);
    if (standardBookNum < 1 || standardBookNum > 66) return "";
    
    String bookCode = _sabdaCodes[standardBookNum];
    String bookPrefix = standardBookNum.toString().padLeft(2, '0');
    String chapterPrefix = chapter.toString().padLeft(2, '0');
    
    return "https://media.sabda.org/alkitab_audio/tb/${bookPrefix}_${bookCode}/${bookPrefix}_${bookCode}${chapterPrefix}.mp3";
  }

  Future<void> _playPauseAudio() async {
    try {
      if (_isPlaying) { 
        await _audioPlayer.pause(); 
      } else {
        setState(() => _isAudioLoading = true);
        String audioUrl = _getAudioUrl(_currentBookNum, _currentChapter);
        
        // 👇 PERBAIKAN ERROR: FORMAT BARU UNTUK AUDIO CONTEXT 👇
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
            options: {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
        ));

        // Tembak URL Sabda-nya
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

  // --- LOGIKA DATABASE ---
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

  Future<void> _changeVersion(String v) async {
    setState(() { _currentVersion = v; _isLoading = true; });
    if (_db != null) await _db!.close();
    await _loadDatabase();
  }

  // --- MENU HAMBURGER & FITUR TAMBAHAN ---
  void _onMenuSelected(String value) {
    if (value == 'search') {
      Navigator.push(context, MaterialPageRoute(builder: (c) => SearchPage(db: _db!, allBooks: _allBooks, currentBookNum: _currentBookNum))).then((res) {
        if (res != null) {
          setState(() { _currentBookNum = res['book_number']; _currentChapter = res['chapter']; });
          _resetAudio(); _saveLastPosition(); _loadContent(scrollToVerse: res['verse']);
        }
      });
    } else if (value == 'dictionary') {
      _tampilkanDialogKamus(context);
    } else if (value == 'notes') {
      _showNotesManagerDialog();
    }
  }

  void _showNotesManagerDialog() {
    showModalBottomSheet(
      context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.all(20), child: Text("Kelola Catatan", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          ListTile(leading: const Icon(Icons.list_alt, color: Colors.indigo), title: const Text("Lihat Daftar Catatan"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => NoteListPage(prefs: _prefs, db: _db!, allBooks: _allBooks))).then((_) => _loadContent()); }),
          const Divider(),
          ListTile(leading: const Icon(Icons.cloud_upload, color: Colors.green), title: const Text("Backup ke Cloud"), subtitle: const Text("Amankan catatan ke akun Anda"), onTap: () { Navigator.pop(context); _backupNotesToCloud(); }),
          ListTile(leading: const Icon(Icons.cloud_download, color: Colors.orange), title: const Text("Restore dari Cloud"), subtitle: const Text("Kembalikan catatan (jika ganti HP)"), onTap: () { Navigator.pop(context); _restoreNotesFromCloud(); }),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _backupNotesToCloud() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Silakan login dahulu."))); return; }
    setState(() => _isSyncing = true);
    try {
      final allKeys = _prefs.getStringList("ALL_NOTE_KEYS") ?? [];
      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var key in allKeys) {
        String? data = _prefs.getString(key);
        if (data != null) {
          var docRef = FirebaseFirestore.instance.collection("users").doc(user.uid).collection("notes").doc(key);
          batch.set(docRef, {"content": data, "updatedAt": FieldValue.serverTimestamp()});
        }
      }
      await batch.commit();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Backup Berhasil!")));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e"))); } finally { setState(() => _isSyncing = false); }
  }

  Future<void> _restoreNotesFromCloud() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isSyncing = true);
    try {
      var snapshot = await FirebaseFirestore.instance.collection("users").doc(user.uid).collection("notes").get();
      List<String> newKeys = [];
      for (var doc in snapshot.docs) {
        String key = doc.id; String content = doc.data()['content'];
        await _prefs.setString(key, content); newKeys.add(key);
      }
      await _prefs.setStringList("ALL_NOTE_KEYS", newKeys);
      await _loadContent();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Restore Berhasil!")));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e"))); } finally { setState(() => _isSyncing = false); }
  }

  void _showActionMenu() {
    if (_selectedVerses.isEmpty) return;
    List<int> sorted = _selectedVerses.toList()..sort();
    String bookName = _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    String nas = "$bookName $_currentChapter:${sorted.join(",")}";
    showModalBottomSheet(
      context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), 
      builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.all(16), child: Text(nas, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        ListTile(leading: const Icon(Icons.add_comment, color: Colors.blue), title: const Text("Buat Catatan"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: nas, prefs: _prefs, db: _db!, allBooks: _allBooks))).then((_) => _loadContent()); }),
        ListTile(leading: const Icon(Icons.copy), title: const Text("Salin Ayat"), onTap: () { 
          String fullText = "$nas\n";
          for (var vNum in sorted) { var vData = _verses.firstWhere((element) => element['verse'] == vNum); fullText += "$vNum. ${_cleanText(vData['text'])}\n"; }
          Clipboard.setData(ClipboardData(text: fullText)); Navigator.pop(context); setState(() => _selectedVerses.clear()); 
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Disalin ke Klip")));
        }),
      ])
    );
  }

  void _showNoteSelection(List<String> keys) {
    showModalBottomSheet(
      context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => ListView.builder(
        shrinkWrap: true, itemCount: keys.length,
        itemBuilder: (context, i) {
          String key = keys[i]; String raw = _prefs.getString(key) ?? "";
          return ListTile(leading: const Icon(Icons.edit_note), title: Text(raw.split("~|~")[0]), onTap: () { Navigator.pop(context); _openNote(key); });
        },
      ),
    );
  }

  void _openNote(String key) {
    String? raw = _prefs.getString(key);
    if (raw != null) { Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: raw.split("~|~")[0], prefs: _prefs, existingKey: key, db: _db!, allBooks: _allBooks))).then((_) => _loadContent()); }
  }

  void _tampilkanDialogKamus(BuildContext context) {
    final TextEditingController sc = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Kamus Alkitab"),
        content: TextField(controller: sc, autofocus: true, decoration: const InputDecoration(hintText: "Kata kunci...")),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")), ElevatedButton(onPressed: () { Navigator.pop(context); _bukaKamusDiBrowser(sc.text); }, child: const Text("Cari"))],
      ),
    );
  }

  Future<void> _bukaKamusDiBrowser(String k) async {
    if (k.trim().isEmpty) return;
    final Uri url = Uri.parse("https://alkitab.sabda.org/dictionary.php?word=${k.trim()}");
    try { await launchUrl(url, mode: LaunchMode.inAppBrowserView); } catch (e) {}
  }

  void _showNavigation() {
    showGeneralDialog(
      context: context, barrierDismissible: true, barrierLabel: "Nav", barrierColor: Colors.black54,
      pageBuilder: (context, a1, a2) => Align(
        alignment: Alignment.topCenter,
        child: Material(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(25)),
          child: _NavSheet(
            allBooks: _allBooks, db: _db!, currentVersion: _currentVersion,
            onVersionChange: (v) { Navigator.pop(context); _changeVersion(v); },
            onSelectionComplete: (b, c, v) { setState(() { _currentBookNum = b; _currentChapter = c; }); _resetAudio(); _saveLastPosition(); _loadContent(scrollToVerse: v); },
          ),
        ),
      ),
    );
  }

  // 👇 PERIKOP DITENGAHKAN 👇
  Widget _buildPerikopItem(String title) {
    if (!title.contains("<x>")) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.only(top: 25, bottom: 10), 
        child: Text(title, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: _fontSize + 2, color: Colors.indigo.shade900))
      );
    }
    List<InlineSpan> spans = []; final regex = RegExp(r'<x>(.*?)</x>');
    title.splitMapJoin(regex, onMatch: (Match m) {
      String rawRef = m.group(1) ?? ""; final refData = RegExp(r'(\d+)\s+(\d+):(\d+)').firstMatch(rawRef);
      if (refData != null) {
        int bNum = int.parse(refData.group(1)!); int chap = int.parse(refData.group(2)!); int vStart = int.parse(refData.group(3)!);
        String bookShort = bNum.toString(); try { bookShort = _allBooks.firstWhere((b) => b.bookNumber == bNum).shortName; } catch (e) {}
        spans.add(TextSpan(
          text: rawRef.replaceFirst(bNum.toString(), bookShort), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()..onTap = () { setState(() { _currentBookNum = bNum; _currentChapter = chap; }); _resetAudio(); _loadContent(scrollToVerse: vStart); },
        ));
      } else { spans.add(TextSpan(text: rawRef)); }
      return "";
    }, onNonMatch: (text) { spans.add(TextSpan(text: text)); return ""; });
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10), 
      child: RichText(textAlign: TextAlign.center, text: TextSpan(style: TextStyle(fontSize: _fontSize - 3, color: Colors.grey.shade700, fontStyle: FontStyle.italic), children: spans))
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
          if (_isSyncing) const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            onSelected: _onMenuSelected,
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(value: 'search', child: Row(children: [Icon(Icons.search, color: Colors.indigo), SizedBox(width: 10), Text("Pencarian")])),
              const PopupMenuItem(value: 'dictionary', child: Row(children: [Icon(Icons.menu_book, color: Colors.orange), SizedBox(width: 10), Text("Kamus Alkitab")])),
              const PopupMenuItem(value: 'notes', child: Row(children: [Icon(Icons.edit_note, color: Colors.green), SizedBox(width: 10), Text("Kelola Catatan & Backup")])),
            ],
          ),
        ],
        // 👇 AUDIO PLAYER DI HEADER 👇
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
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.stop_circle, color: Colors.redAccent, size: 28), 
                  onPressed: _resetAudio,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
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
      bool isSelected = _selectedVerses.contains(vNum);
      if (_perikopMap.containsKey(vNum)) {
        for (var title in _perikopMap[vNum]!) { content.add(_buildPerikopItem(title)); }
      }
      content.add(
        GestureDetector(
          onLongPress: () { if (!isSelected) setState(() => _selectedVerses.add(vNum)); _showActionMenu(); },
          onTap: () => setState(() => isSelected ? _selectedVerses.remove(vNum) : _selectedVerses.add(vNum)),
          child: Container(
            width: double.infinity,
            color: isSelected ? Colors.blue.withOpacity(0.15) : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(text: TextSpan(style: TextStyle(color: Colors.black87, fontSize: _fontSize, height: 1.6), children: [
                  TextSpan(text: "$vNum. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                  TextSpan(text: _cleanText(v['text'])),
                ])),
                if (_verseNotesMap.containsKey(vNum))
                  Padding(
                    padding: const EdgeInsets.only(top: 8), 
                    child: InkWell(
                      onTap: () => _showNoteSelection(_verseNotesMap[vNum]!), 
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.edit_note, size: 16, color: Colors.orange),
                        const SizedBox(width: 4),
                        Text("Lihat Catatan", style: TextStyle(fontSize: _fontSize - 4, color: Colors.orange.shade800, fontStyle: FontStyle.italic)),
                      ])
                    )
                  ),
              ],
            ),
          ),
        )
      );
    }
    return content;
  }
}

// --- NAV SHEET MEWAH ---
class _NavSheet extends StatefulWidget {
  final List<BibleBook> allBooks; final Database db; final String currentVersion; final Function(String) onVersionChange; final Function(int, int, int) onSelectionComplete;
  const _NavSheet({required this.allBooks, required this.db, required this.currentVersion, required this.onVersionChange, required this.onSelectionComplete});
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
  Widget build(BuildContext context) => SafeArea(bottom: false, child: _buildContent());
  Widget _buildContent() {
    if (selChapter != null) return _buildGrid("Ayat: ${selBook!.name} $selChapter", verses, (v) { widget.onSelectionComplete(selBook!.bookNumber, selChapter!, v); Navigator.pop(context); }, () => setState(() => selChapter = null));
    if (selBook != null) return _buildGrid("Pasal: ${selBook!.name}", chapters, (c) => _getVerses(c), () => setState(() => selBook = null));
    List<BibleBook> pl = widget.allBooks.where((b) => b.bookNumber < 470).toList();
    List<BibleBook> pb = widget.allBooks.where((b) => b.bookNumber >= 470).toList();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.all(16), color: Colors.indigo[50], child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text("Versi:", style: TextStyle(fontWeight: FontWeight.bold)),
        DropdownButton<String>(value: widget.currentVersion, items: const [DropdownMenuItem(value: "TB.SQLite3", child: Text("TB")), DropdownMenuItem(value: "TJL.SQLite3", child: Text("TJL"))], onChanged: (v) => widget.onVersionChange(v!)),
      ])),
      Flexible(child: ListView(shrinkWrap: true, children: [_header("PERJANJIAN LAMA", Colors.pink), _kitabGrid(pl), const Divider(), _header("PERJANJIAN BARU", Colors.blue), _kitabGrid(pb)]))
    ]);
  }
  Widget _buildGrid(String t, List<int> items, Function(int) onTap, VoidCallback onBack) => Column(mainAxisSize: MainAxisSize.min, children: [AppBar(title: Text(t, style: const TextStyle(fontSize: 16, color: Colors.black)), leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: onBack), backgroundColor: Colors.transparent, elevation: 0), Flexible(child: GridView.builder(shrinkWrap: true, padding: const EdgeInsets.all(12), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 60, childAspectRatio: 1.2, mainAxisSpacing: 6, crossAxisSpacing: 6), itemCount: items.length, itemBuilder: (ctx, i) => InkWell(onTap: () => onTap(items[i]), child: Container(alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: Text("${items[i]}", style: const TextStyle(fontWeight: FontWeight.bold))))))]);
  Widget _header(String t, Color c) => Padding(padding: const EdgeInsets.all(12), child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12)));
  Widget _kitabGrid(List<BibleBook> books) => GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 12), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 68, childAspectRatio: 1.9, mainAxisSpacing: 6, crossAxisSpacing: 6), itemCount: books.length, itemBuilder: (ctx, i) => InkWell(onTap: () => _getChapters(books[i]), child: Container(alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)), child: Text(books[i].shortName.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))));
}