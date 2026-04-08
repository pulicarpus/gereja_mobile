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

  // DAFTAR FOLDER & PREFIX FILE (KEJ - WAH) UNTUK GITHUB BOS
  final Map<int, Map<String, String>> _bibleAudioMap = {
    1: {"folder": "kejadian", "file": "01_kej"},
    2: {"folder": "keluaran", "file": "02_kel"},
    3: {"folder": "imamat", "file": "03_ima"},
    4: {"folder": "bilangan", "file": "04_bil"},
    5: {"folder": "ulangan", "file": "05_ula"},
    6: {"folder": "yosua", "file": "06_yos"},
    7: {"folder": "hakim-hakim", "file": "07_hak"},
    8: {"folder": "rut", "file": "08_rut"},
    9: {"folder": "1samuel", "file": "09_1sa"},
    10: {"folder": "2samuel", "file": "10_2sa"},
    11: {"folder": "1raja-raja", "file": "11_1ra"},
    12: {"folder": "2raja-raja", "file": "12_2ra"},
    13: {"folder": "1tawarikh", "file": "13_1ta"},
    14: {"folder": "2tawarikh", "file": "14_2ta"},
    15: {"folder": "ezra", "file": "15_ezr"},
    16: {"folder": "nehemia", "file": "16_neh"},
    17: {"folder": "ester", "file": "17_est"},
    18: {"folder": "ayub", "file": "18_ayu"},
    19: {"folder": "mazmur", "file": "19_maz"},
    20: {"folder": "amsal", "file": "20_ams"},
    21: {"folder": "pengkhotbah", "file": "21_pen"},
    22: {"folder": "kidungagung", "file": "22_kid"},
    23: {"folder": "yesaya", "file": "23_yes"},
    24: {"folder": "yeremia", "file": "24_yer"},
    25: {"folder": "ratapan", "file": "25_rat"},
    26: {"folder": "yehezkiel", "file": "26_yeh"},
    27: {"folder": "daniel", "file": "27_dan"},
    28: {"folder": "hosea", "file": "28_hos"},
    29: {"folder": "yoel", "file": "29_yoe"},
    30: {"folder": "amos", "file": "30_amo"},
    31: {"folder": "obaja", "file": "31_oba"},
    32: {"folder": "yunus", "file": "32_yun"},
    33: {"folder": "mikha", "file": "33_mik"},
    34: {"folder": "nahum", "file": "34_nah"},
    35: {"folder": "habakuk", "file": "35_hab"},
    36: {"folder": "zefanya", "file": "36_zef"},
    37: {"folder": "hagai", "file": "37_hag"},
    38: {"folder": "zakharia", "file": "38_zak"},
    39: {"folder": "maleakhi", "file": "39_mal"},
    40: {"folder": "matius", "file": "01_mat"},
    41: {"folder": "markus", "file": "02_mar"},
    42: {"folder": "lukas", "file": "03_luk"},
    43: {"folder": "yohanes", "file": "04_yoh"},
    44: {"folder": "kisahpararasul", "file": "05_kis"},
    45: {"folder": "roma", "file": "06_rom"},
    46: {"folder": "1korintus", "file": "07_1ko"},
    47: {"folder": "2korintus", "file": "08_2ko"},
    48: {"folder": "galatia", "file": "09_gal"},
    49: {"folder": "efesus", "file": "10_efe"},
    50: {"folder": "filipi", "file": "11_flp"},
    51: {"folder": "kolose", "file": "12_kol"},
    52: {"folder": "1tesalonika", "file": "13_1te"},
    53: {"folder": "2tesalonika", "file": "14_2te"},
    54: {"folder": "1timotius", "file": "15_1ti"},
    55: {"folder": "2timotius", "file": "16_2ti"},
    56: {"folder": "titus", "file": "17_tit"},
    57: {"folder": "filemon", "file": "18_fil"},
    58: {"folder": "ibrani", "file": "19_ibr"},
    59: {"folder": "yakobus", "file": "20_yak"},
    60: {"folder": "1petrus", "file": "21_1pe"},
    61: {"folder": "2petrus", "file": "22_2pe"},
    62: {"folder": "1yohanes", "file": "23_1yo"},
    63: {"folder": "2yohanes", "file": "24_2yo"},
    64: {"folder": "3yohanes", "file": "25_3yo"},
    65: {"folder": "yudas", "file": "26_yud"},
    66: {"folder": "wahyu", "file": "27_wah"},
  };

  @override
  void initState() {
    super.initState();
    _initApp();
    _setupAudioListeners();
  }

  void _setupAudioListeners() {
    _audioPlayer.onPlayerStateChanged.listen((state) { if (mounted) setState(() => _isPlaying = state == PlayerState.playing); });
    _audioPlayer.onDurationChanged.listen((d) { if (mounted) setState(() => _duration = d); });
    _audioPlayer.onPositionChanged.listen((p) { if (mounted) setState(() => _position = p); });
    _audioPlayer.onPlayerComplete.listen((e) { if (mounted) setState(() { _isPlaying = false; _position = Duration.zero; }); });
  }

  @override
  void dispose() { _audioPlayer.dispose(); _scrollController.dispose(); super.dispose(); }

  // --- AUDIO LOGIC ---
  String _getAudioUrl(int bookNum, int chapter) {
    int standardBookNum = bookNum < 400 ? (bookNum ~/ 10) : (((bookNum - 470) ~/ 10) + 40);
    String chapterStr = chapter.toString().padLeft(2, '0');
    if (_bibleAudioMap.containsKey(standardBookNum)) {
      String folder = _bibleAudioMap[standardBookNum]!["folder"]!;
      String prefix = _bibleAudioMap[standardBookNum]!["file"]!;
      return "https://raw.githubusercontent.com/pulicarpus/gereja_mobile/master/audio/$folder/$prefix$chapterStr.mp3";
    }
    return "";
  }

  Future<void> _playPauseAudio() async {
    String audioUrl = _getAudioUrl(_currentBookNum, _currentChapter);
    if (audioUrl.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Audio belum tersedia di folder GitHub."))); return; }
    try {
      if (_isPlaying) { await _audioPlayer.pause(); } 
      else {
        setState(() => _isAudioLoading = true);
        await _audioPlayer.setAudioContext(AudioContext(
          android: const AudioContextAndroid(isSpeakerphoneOn: true, stayAwake: true, contentType: AndroidContentType.music, usageType: AndroidUsageType.media, audioFocus: AndroidAudioFocus.gain),
          iOS: const AudioContextIOS(category: AVAudioSessionCategory.playback, options: [AVAudioSessionOptions.defaultToSpeaker, AVAudioSessionOptions.mixWithOthers]),
        ));
        await _audioPlayer.play(UrlSource(audioUrl));
        setState(() => _isAudioLoading = false);
      }
    } catch (e) { setState(() => _isAudioLoading = false); }
  }

  void _resetAudio() { _audioPlayer.stop(); setState(() { _isPlaying = false; _position = Duration.zero; }); }

  // --- CORE LOGIC ---
  Future<void> _initApp() async {
    _prefs = await SharedPreferences.getInstance();
    _currentBookNum = _prefs.getInt('LAST_BOOK_NUM') ?? 10; 
    _currentChapter = _prefs.getInt('LAST_CHAPTER') ?? 1;
    _fontSize = _prefs.getDouble('LAST_FONT_SIZE') ?? 18.0;
    await _loadDatabase();
  }

  void _saveLastPosition() { _prefs.setInt('LAST_BOOK_NUM', _currentBookNum); _prefs.setInt('LAST_CHAPTER', _currentChapter); }

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
      setState(() { _allBooks = bookData.map((e) => BibleBook(bookNumber: e['book_number'] as int, name: e['long_name'].toString(), shortName: e['short_name'].toString())).toList(); });
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
      for (var s in storyData) { int vNum = s['verse'] as int; if (!_perikopMap.containsKey(vNum)) _perikopMap[vNum] = []; _perikopMap[vNum]!.add(s['title'].toString()); }
      _verses = verseData;
      _syncNotes();
      setState(() { _isLoading = false; _selectedVerses.clear(); });
      if (scrollToVerse != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollController.hasClients) _scrollController.animateTo((scrollToVerse - 1) * (_fontSize * 3.5), duration: const Duration(milliseconds: 600), curve: Curves.easeOut); });
      }
    } catch (e) { setState(() => _isLoading = false); }
  }

  void _syncNotes() {
    _verseNotesMap.clear();
    final allKeys = _prefs.getStringList("ALL_NOTE_KEYS") ?? [];
    if (_allBooks.isEmpty) return;
    String bName = _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    String prefix = "$bName $_currentChapter:";
    for (var key in allKeys) {
      String? raw = _prefs.getString(key);
      if (raw != null && raw.split("~|~")[0].startsWith(prefix)) {
        try { int v = int.parse(raw.split("~|~")[0].split(":")[1].split(RegExp(r'[-,]')).last); if (!_verseNotesMap.containsKey(v)) _verseNotesMap[v] = []; _verseNotesMap[v]!.add(key); } catch (e) {}
      }
    }
  }

  String _cleanText(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  // 👇 PENANGKAP SINYAL DARI HALAMAN CATATAN 👇
  void _handleNavResult(dynamic res) {
    if (res != null && res is Map && res.containsKey('book_number')) {
      // Jika balik dari tombol "Menuju Pasal Ini"
      setState(() { _currentBookNum = res['book_number']; _currentChapter = res['chapter']; });
      _resetAudio(); _saveLastPosition(); _loadContent(scrollToVerse: res['verse']);
    } else {
      // Jika cuma balik sehabis save catatan biasa
      _loadContent(); 
    }
  }

  // --- ACTIONS & MENU ---
  void _onMenuSelected(String val) {
    if (val == 'search') {
      Navigator.push(context, MaterialPageRoute(builder: (c) => SearchPage(db: _db!, allBooks: _allBooks, currentBookNum: _currentBookNum))).then(_handleNavResult);
    } else if (val == 'dictionary') {
      _showDictionary();
    } else if (val == 'notes') {
      _showNotesManager();
    }
  }

  void _showDictionary() {
    final sc = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(title: const Text("Kamus Alkitab"), content: TextField(controller: sc, autofocus: true, decoration: const InputDecoration(hintText: "Cari kata...")), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("Batal")), ElevatedButton(onPressed: () { Navigator.pop(c); launchUrl(Uri.parse("https://alkitab.sabda.org/dictionary.php?word=${sc.text}"), mode: LaunchMode.inAppBrowserView); }, child: const Text("Cari"))]));
  }

  void _showNotesManager() {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(20), child: Text("Kelola Catatan", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
      ListTile(leading: const Icon(Icons.list_alt, color: Colors.indigo), title: const Text("Lihat Daftar Catatan"), onTap: () { Navigator.pop(c); Navigator.push(context, MaterialPageRoute(builder: (c) => NoteListPage(prefs: _prefs, db: _db!, allBooks: _allBooks))).then(_handleNavResult); }),
      const Divider(),
      ListTile(leading: const Icon(Icons.cloud_upload, color: Colors.green), title: const Text("Backup ke Cloud"), onTap: () { Navigator.pop(c); _syncCloud(true); }),
      ListTile(leading: const Icon(Icons.cloud_download, color: Colors.orange), title: const Text("Restore dari Cloud"), onTap: () { Navigator.pop(c); _syncCloud(false); }),
      const SizedBox(height: 20),
    ]));
  }

  Future<void> _syncCloud(bool isBackup) async {
    final user = FirebaseAuth.instance.currentUser; if (user == null) return;
    setState(() => _isSyncing = true);
    try {
      if (isBackup) {
        final allKeys = _prefs.getStringList("ALL_NOTE_KEYS") ?? [];
        WriteBatch batch = FirebaseFirestore.instance.batch();
        for (var key in allKeys) { String? d = _prefs.getString(key); if (d != null) batch.set(FirebaseFirestore.instance.collection("users").doc(user.uid).collection("notes").doc(key), {"content": d, "updatedAt": FieldValue.serverTimestamp()}); }
        await batch.commit();
      } else {
        var snap = await FirebaseFirestore.instance.collection("users").doc(user.uid).collection("notes").get();
        List<String> keys = []; for (var d in snap.docs) { await _prefs.setString(d.id, d.data()['content']); keys.add(d.id); }
        await _prefs.setStringList("ALL_NOTE_KEYS", keys); await _loadContent();
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isBackup ? "Backup Berhasil" : "Restore Berhasil")));
    } catch (e) {} finally { setState(() => _isSyncing = false); }
  }

  void _showActionMenu() {
    if (_selectedVerses.isEmpty) return;
    List<int> sorted = _selectedVerses.toList()..sort();
    String bName = _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    String nas = "$bName $_currentChapter:${sorted.join(",")}";
    showModalBottomSheet(context: context, builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.all(16), child: Text(nas, style: const TextStyle(fontWeight: FontWeight.bold))),
      ListTile(leading: const Icon(Icons.copy), title: const Text("Salin Ayat"), onTap: () {
        String txt = "$nas\n"; for (var v in sorted) { var d = _verses.firstWhere((e) => e['verse'] == v); txt += "$v. ${_cleanText(d['text'])}\n"; }
        Clipboard.setData(ClipboardData(text: txt)); Navigator.pop(context); setState(() => _selectedVerses.clear());
      }),
      ListTile(leading: const Icon(Icons.add_comment, color: Colors.blue), title: const Text("Buat Catatan"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: nas, prefs: _prefs, db: _db!, allBooks: _allBooks))).then(_handleNavResult); }),
    ]));
  }

  void _handleNoteClick(int vNum, List<String>? keys) {
    String bName = _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    String ref = "$bName $_currentChapter:$vNum";
    if (keys == null || keys.isEmpty) {
      Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: ref, prefs: _prefs, db: _db!, allBooks: _allBooks))).then(_handleNavResult);
    } else if (keys.length == 1) {
      _openNote(keys.first);
    } else {
      showModalBottomSheet(context: context, builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.all(16), child: Text("Pilih Catatan ($ref)", style: const TextStyle(fontWeight: FontWeight.bold))),
        ...keys.map((k) => ListTile(leading: const Icon(Icons.note, color: Colors.orange), title: Text(_prefs.getString(k)?.split("~|~")[1].characters.take(30).toString() ?? ""), onTap: () { Navigator.pop(c); _openNote(k); }))
      ]));
    }
  }

  void _openNote(String k) {
    String? raw = _prefs.getString(k);
    if (raw != null) Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: raw.split("~|~")[0], prefs: _prefs, existingKey: k, db: _db!, allBooks: _allBooks))).then(_handleNavResult);
  }

  // --- UI BUILDING ---
  @override
  Widget build(BuildContext context) {
    String bName = _allBooks.isEmpty ? "" : _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
        title: InkWell(onTap: _showNavigation, child: Row(mainAxisSize: MainAxisSize.min, children: [Text("$bName $_currentChapter"), const Icon(Icons.arrow_drop_down)])),
        actions: [
          if (_isSyncing) const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
          PopupMenuButton<String>(icon: const Icon(Icons.menu), onSelected: _onMenuSelected, itemBuilder: (c) => [
            const PopupMenuItem(value: 'search', child: Row(children: [Icon(Icons.search, color: Colors.indigo), SizedBox(width: 10), Text("Pencarian")])),
            const PopupMenuItem(value: 'dictionary', child: Row(children: [Icon(Icons.menu_book, color: Colors.orange), SizedBox(width: 10), Text("Kamus Alkitab")])),
            const PopupMenuItem(value: 'notes', child: Row(children: [Icon(Icons.edit_note, color: Colors.green), SizedBox(width: 10), Text("Kelola Catatan")])),
          ]),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(45), child: Container(color: Colors.indigo[800], padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), child: Row(children: [
          IconButton(icon: _isAudioLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.orange, size: 30), onPressed: _playPauseAudio),
          Expanded(child: SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), activeTrackColor: Colors.orange, inactiveTrackColor: Colors.white30, thumbColor: Colors.white), child: Slider(value: _position.inSeconds.toDouble(), max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0, onChanged: (v) => _audioPlayer.seek(Duration(seconds: v.toInt()))))),
          IconButton(icon: const Icon(Icons.stop_circle, color: Colors.redAccent, size: 28), onPressed: _resetAudio),
        ]))),
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : GestureDetector(
        onScaleStart: (d) => _baseFontSize = _fontSize,
        onScaleUpdate: (d) => setState(() => _fontSize = (_baseFontSize * d.scale).clamp(12.0, 40.0)),
        onScaleEnd: (d) => _prefs.setDouble('LAST_FONT_SIZE', _fontSize),
        child: ListView(
          controller: _scrollController, padding: const EdgeInsets.all(15),
          children: [Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _buildContent()))],
        ),
      ),
    );
  }

  // 👇 PERBAIKAN IKON CATATAN DI UJUNG KANAN & LEBIH BESAR 👇
  List<Widget> _buildContent() {
    List<Widget> content = [];
    for (var v in _verses) {
      int vNum = v['verse'] as int; bool isSel = _selectedVerses.contains(vNum);
      if (_perikopMap.containsKey(vNum)) { for (var t in _perikopMap[vNum]!) content.add(Container(width: double.infinity, padding: const EdgeInsets.only(top: 25, bottom: 10), child: Text(t, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: _fontSize + 2, color: Colors.indigo.shade900)))); }
      
      content.add(GestureDetector(
        onLongPress: () { if (!isSel) setState(() => _selectedVerses.add(vNum)); _showActionMenu(); },
        onTap: () => setState(() => isSel ? _selectedVerses.remove(vNum) : _selectedVerses.add(vNum)),
        child: Container(
          color: isSel ? Colors.blue.withOpacity(0.15) : Colors.transparent, 
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RichText(text: TextSpan(style: TextStyle(color: Colors.black87, fontSize: _fontSize, height: 1.6), children: [
                  TextSpan(text: "$vNum. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                  TextSpan(text: _cleanText(v['text'])),
                ])),
              ),
              if (_verseNotesMap.containsKey(vNum))
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                  child: InkWell(
                    onTap: () => _handleNoteClick(vNum, _verseNotesMap[vNum]),
                    child: const Icon(Icons.edit_note, size: 28, color: Colors.orange),
                  ),
                ),
            ],
          ),
        ),
      ));
    }
    return content;
  }

  void _showNavigation() { showGeneralDialog(context: context, barrierDismissible: true, barrierLabel: "Nav", barrierColor: Colors.black54, pageBuilder: (c, a1, a2) => Align(alignment: Alignment.topCenter, child: Material(borderRadius: const BorderRadius.vertical(bottom: Radius.circular(25)), child: _NavSheet(allBooks: _allBooks, db: _db!, onSelectionComplete: (b, c, v) { 
    Navigator.pop(context); // 👇 PERBAIKAN: Dialog Navigasi Menutup Otomatis
    setState(() { _currentBookNum = b; _currentChapter = c; }); 
    _resetAudio(); _saveLastPosition(); _loadContent(scrollToVerse: v); 
  })))); }
}

class _NavSheet extends StatefulWidget {
  final List<BibleBook> allBooks; final Database db; final Function(int, int, int) onSelectionComplete;
  const _NavSheet({required this.allBooks, required this.db, required this.onSelectionComplete});
  @override State<_NavSheet> createState() => _NavSheetState();
}
class _NavSheetState extends State<_NavSheet> {
  BibleBook? selB; int? selC; List<int> chs = []; List<int> vrs = [];
  void _getChapters(BibleBook b) async { final res = await widget.db.rawQuery("SELECT DISTINCT chapter FROM verses WHERE book_number = ? ORDER BY chapter ASC", [b.bookNumber]); setState(() { selB = b; chs = res.map((e) => e['chapter'] as int).toList(); selC = null; }); }
  void _getVerses(int c) async { final res = await widget.db.rawQuery("SELECT verse FROM verses WHERE book_number = ? AND chapter = ? ORDER BY verse ASC", [selB!.bookNumber, c]); setState(() { selC = c; vrs = res.map((e) => e['verse'] as int).toList(); }); }
  @override 
  Widget build(BuildContext context) => SafeArea(child: Container(constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8), child: Column(mainAxisSize: MainAxisSize.min, children: [
    AppBar(backgroundColor: Colors.transparent, elevation: 0, foregroundColor: Colors.black, title: Text(selB == null ? "Pilih Kitab" : (selC == null ? selB!.name : "${selB!.name} $selC")), leading: selB != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => selC != null ? selC = null : selB = null)) : null),
    const Divider(height: 1),
    Expanded(child: _buildGrid()),
  ])));
  Widget _buildGrid() {
    if (selC != null) return _grid(vrs, (v) => widget.onSelectionComplete(selB!.bookNumber, selC!, v));
    if (selB != null) return _grid(chs, (c) => _getVerses(c));
    return ListView(children: [_header("PERJANJIAN LAMA", Colors.pink), _kGrid(widget.allBooks.where((b) => b.bookNumber < 400).toList()), _header("PERJANJIAN BARU", Colors.blue), _kGrid(widget.allBooks.where((b) => b.bookNumber >= 400).toList())]);
  }
  Widget _header(String t, Color c) => Padding(padding: const EdgeInsets.all(15), child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold)));
  Widget _kGrid(List<BibleBook> bks) => GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 10), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 70, childAspectRatio: 2, mainAxisSpacing: 5, crossAxisSpacing: 5), itemCount: bks.length, itemBuilder: (c, i) => InkWell(onTap: () => _getChapters(bks[i]), child: Container(alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(5)), child: Text(bks[i].shortName.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)))));
  Widget _grid(List<int> its, Function(int) onTap) => GridView.builder(padding: const EdgeInsets.all(15), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 60, mainAxisSpacing: 10, crossAxisSpacing: 10), itemCount: its.length, itemBuilder: (c, i) => InkWell(onTap: () => onTap(its[i]), child: Container(alignment: Alignment.center, decoration: BoxDecoration(color: Colors.indigo[50], borderRadius: BorderRadius.circular(10)), child: Text("${its[i]}", style: const TextStyle(fontWeight: FontWeight.bold)))));
}