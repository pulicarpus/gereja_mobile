import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart'; 
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Source;
import 'package:firebase_auth/firebase_auth.dart';     
import 'package:audioplayers/audioplayers.dart'; 
import 'package:path_provider/path_provider.dart';

import 'bible_models.dart';
import 'notes_pages.dart';
import 'search_page.dart';
import 'offline_audio_page.dart';
import 'kamus_page.dart';
import 'loading_sultan.dart';
import 'buat_gambar_page.dart'; 

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
  final GlobalKey _targetVerseKey = GlobalKey();

  Map<String, dynamic> _highlights = {}; 

  String _currentVersion = "TB.SQLite3"; 
  int _currentBookNum = 10; 
  int _currentChapter = 1;
  int _currentVerse = 1; 
  int? _highlightedVerse; 
  bool _isLoading = true;
  bool _isSyncing = false; 
  late SharedPreferences _prefs;

  double _fontSize = 18.0;
  double _baseFontSize = 18.0;
  Map<int, Offset> _pointerPositions = {};
  double _initialPinchDistance = 0.0;
  double _initialFontSize = 18.0;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isAudioLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  final Map<int, Map<String, String>> _bibleAudioMap = {
    1: {"folder": "kejadian", "file": "01_kej"}, 2: {"folder": "keluaran", "file": "02_kel"}, 3: {"folder": "imamat", "file": "03_ima"}, 4: {"folder": "bilangan", "file": "04_bil"}, 5: {"folder": "ulangan", "file": "05_ula"}, 6: {"folder": "yosua", "file": "06_yos"}, 7: {"folder": "hakim-hakim", "file": "07_hak"}, 8: {"folder": "rut", "file": "08_rut"}, 9: {"folder": "1samuel", "file": "09_1sa"}, 10: {"folder": "2samuel", "file": "10_2sa"}, 11: {"folder": "1raja-raja", "file": "11_1Kings_"}, 12: {"folder": "2raja-raja", "file": "12_2Kings_"}, 13: {"folder": "1tawarikh", "file": "13_1Chronicles_"}, 14: {"folder": "2tawarikh", "file": "14_2Chronicles_"}, 15: {"folder": "ezra", "file": "15_ezr"}, 16: {"folder": "nehemia", "file": "16_neh"}, 17: {"folder": "ester", "file": "17_est"}, 18: {"folder": "ayub", "file": "18_ayb"}, 19: {"folder": "mazmur", "file": "19_mzm"}, 20: {"folder": "amsal", "file": "20_ams"}, 21: {"folder": "pengkhotbah", "file": "21_pkh"}, 22: {"folder": "kidungagung", "file": "22_kid"}, 23: {"folder": "yesaya", "file": "23_yes"}, 24: {"folder": "yeremia", "file": "24_yer"}, 25: {"folder": "ratapan", "file": "25_rat"}, 26: {"folder": "yehezkiel", "file": "26_yeh"}, 27: {"folder": "daniel", "file": "27_dan"}, 28: {"folder": "hosea", "file": "28_hos"}, 29: {"folder": "yoel", "file": "29_yoe"}, 30: {"folder": "amos", "file": "30_amo"}, 31: {"folder": "obaja", "file": "31_oba"}, 32: {"folder": "yunus", "file": "32_yun"}, 33: {"folder": "mikha", "file": "33_mik"}, 34: {"folder": "nahum", "file": "34_nah"}, 35: {"folder": "habakuk", "file": "35_hab"}, 36: {"folder": "zefanya", "file": "36_zef"}, 37: {"folder": "hagai", "file": "37_hag"}, 38: {"folder": "zakharia", "file": "38_zak"}, 39: {"folder": "maleakhi", "file": "39_mal"},
    40: {"folder": "matius", "file": "01_mat"}, 41: {"folder": "markus", "file": "02_mrk"}, 42: {"folder": "lukas", "file": "03_luk"}, 43: {"folder": "yohanes", "file": "04_yoh"}, 44: {"folder": "kisahpararasul", "file": "05_kis"}, 45: {"folder": "roma", "file": "06_rom"}, 46: {"folder": "1korintus", "file": "07_1ko"}, 47: {"folder": "2korintus", "file": "08_2ko"}, 48: {"folder": "galatia", "file": "09_gal"}, 49: {"folder": "efesus", "file": "10_efe"}, 50: {"folder": "filipi", "file": "11_fil"}, 51: {"folder": "kolose", "file": "12_kol"}, 52: {"folder": "1tesalonika", "file": "13_1te"}, 53: {"folder": "2tesalonika", "file": "14_2te"}, 54: {"folder": "1timotius", "file": "15_1ti"}, 55: {"folder": "2timotius", "file": "16_2ti"}, 56: {"folder": "titus", "file": "17_tit"}, 57: {"folder": "filemon", "file": "18_flm"}, 58: {"folder": "ibrani", "file": "19_ibr"}, 59: {"folder": "yakobus", "file": "20_yak"}, 60: {"folder": "1petrus", "file": "21_1pe"}, 61: {"folder": "2petrus", "file": "22_2pe"}, 62: {"folder": "1yohanes", "file": "23_1yo"}, 63: {"folder": "2yohanes", "file": "24_2yo"}, 64: {"folder": "3yohanes", "file": "25_3yo"}, 65: {"folder": "yudas", "file": "26_yud"}, 66: {"folder": "wahyu", "file": "27_wah"},
  };

  @override
  void initState() { super.initState(); _initApp(); _setupAudioListeners(); }

  void _setupAudioListeners() {
    _audioPlayer.onPlayerStateChanged.listen((state) { if (mounted) setState(() => _isPlaying = state == PlayerState.playing); });
    _audioPlayer.onDurationChanged.listen((d) { if (mounted) setState(() => _duration = d); });
    _audioPlayer.onPositionChanged.listen((p) { if (mounted) setState(() => _position = p); });
    _audioPlayer.onPlayerComplete.listen((e) { if (mounted) setState(() { _isPlaying = false; _position = Duration.zero; }); });
  }

  @override
  void dispose() { _audioPlayer.dispose(); _scrollController.dispose(); super.dispose(); }

  Future<void> _initApp() async {
    _prefs = await SharedPreferences.getInstance();
    _currentBookNum = _prefs.getInt('LAST_BOOK_NUM') ?? 10; 
    _currentChapter = _prefs.getInt('LAST_CHAPTER') ?? 1;
    _currentVerse = _prefs.getInt('LAST_VERSE') ?? 1;
    _fontSize = _prefs.getDouble('LAST_FONT_SIZE') ?? 18.0;

    String? hStr = _prefs.getString('BIBLE_HIGHLIGHTS');
    if (hStr != null) _highlights = jsonDecode(hStr);

    await _loadDatabase();
    if (_currentVerse > 1) { Future.delayed(const Duration(milliseconds: 800), () { _loadContent(scrollToVerse: _currentVerse); }); }
  }

  void _saveLastPosition(int verse) { _prefs.setInt('LAST_BOOK_NUM', _currentBookNum); _prefs.setInt('LAST_CHAPTER', _currentChapter); _prefs.setInt('LAST_VERSE', verse); }
  void _saveHighlightsToPrefs() { _prefs.setString('BIBLE_HIGHLIGHTS', jsonEncode(_highlights)); }

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
        setState(() => _highlightedVerse = scrollToVerse); 
        WidgetsBinding.instance.addPostFrameCallback((_) { 
          if (_targetVerseKey.currentContext != null) {
            Scrollable.ensureVisible(_targetVerseKey.currentContext!, duration: const Duration(milliseconds: 600), curve: Curves.easeInOut, alignment: 0.3);
          } else if (_scrollController.hasClients) {
            _scrollController.animateTo((scrollToVerse - 1) * (_fontSize * 4.5), duration: const Duration(milliseconds: 600), curve: Curves.easeOut); 
          }
        });
        Future.delayed(const Duration(seconds: 3), () { if (mounted) setState(() => _highlightedVerse = null); });
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

  void _showActionMenu() {
    if (_selectedVerses.isEmpty) return;
    List<int> sorted = _selectedVerses.toList()..sort();
    String bName = _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    String nas = "$bName $_currentChapter:${_formatVerses(sorted)}";
    
    showModalBottomSheet(context: context, builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.all(16), child: Text(nas, style: const TextStyle(fontWeight: FontWeight.bold))),
      ListTile(leading: const Icon(Icons.copy), title: const Text("Salin Ayat"), onTap: () {
        String txt = "$nas\n"; for (var v in sorted) { var d = _verses.firstWhere((e) => e['verse'] == v); txt += "$v. ${_cleanText(d['text'])}\n"; }
        Clipboard.setData(ClipboardData(text: txt)); Navigator.pop(context); setState(() => _selectedVerses.clear());
      }),
      ListTile(leading: const Icon(Icons.add_comment, color: Colors.blue), title: const Text("Buat Catatan"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: nas, prefs: _prefs, db: _db!, allBooks: _allBooks))).then(_handleNavResult); }),
      ListTile(leading: const Icon(Icons.edit_attributes, color: Colors.orange), title: const Text("Beri Stabilo & Label"), onTap: () { Navigator.pop(context); _showStabiloDialog(sorted); }),
      ListTile(leading: const Icon(Icons.image, color: Colors.purple), title: const Text("Jadikan Gambar"), onTap: () { Navigator.pop(context); String txt = ""; for (var v in sorted) { var d = _verses.firstWhere((e) => e['verse'] == v); txt += "${_cleanText(d['text'])} "; } Navigator.push(context, MaterialPageRoute(builder: (c) => BuatGambarPage(ayatTeks: txt.trim(), referensi: nas))); setState(() => _selectedVerses.clear()); }),
    ]));
  }

  void _showStabiloDialog(List<int> verses) {
    String label = "";
    int colorValue = Colors.yellow.withOpacity(0.3).value;
    showDialog(context: context, builder: (c) => AlertDialog(
        title: const Text("Stabilo & Label"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [ const Text("Pilih Warna:"), const SizedBox(height: 10), Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [ _colorCircle(Colors.yellow, (v) => colorValue = v), _colorCircle(Colors.greenAccent, (v) => colorValue = v), _colorCircle(Colors.lightBlueAccent, (v) => colorValue = v), _colorCircle(Colors.pinkAccent, (v) => colorValue = v), ]), const SizedBox(height: 20), TextField(decoration: const InputDecoration(labelText: "Label (Cth: Kasih, Janji)", border: OutlineInputBorder()), onChanged: (v) => label = v) ]),
        actions: [ TextButton(onPressed: () { setState(() { for (var v in verses) { _highlights.remove("${_currentBookNum}_${_currentChapter}_$v"); } }); _saveHighlightsToPrefs(); Navigator.pop(c); setState(() => _selectedVerses.clear()); }, child: const Text("Hapus", style: TextStyle(color: Colors.red))), ElevatedButton(onPressed: () { setState(() { for (var v in verses) { _highlights["${_currentBookNum}_${_currentChapter}_$v"] = { "color": colorValue, "label": label.trim() }; } }); _saveHighlightsToPrefs(); Navigator.pop(c); setState(() => _selectedVerses.clear()); }, child: const Text("Simpan")) ]
    ));
  }

  Widget _colorCircle(Color color, Function(int) onSelect) => InkWell(onTap: () => onSelect(color.withOpacity(0.3).value), child: CircleAvatar(backgroundColor: color, radius: 15));
  String _cleanText(String text) => text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  String _formatVerses(List<int> vs) { if (vs.isEmpty) return ""; vs.sort(); List<String> groups = []; int start = vs.first, end = vs.first; for (int i = 1; i < vs.length; i++) { if (vs[i] == end + 1) { end = vs[i]; } else { groups.add(start == end ? "$start" : "$start-$end"); start = vs[i]; end = vs[i]; } } groups.add(start == end ? "$start" : "$start-$end"); return groups.join(", "); }

  // 👇 INI DIA KUNCI PERBAIKAN FITUR KLIK MENU & KEMBALI DARI CATATAN 👇
  void _onMenuSelected(String v) { 
    if (v == 'search') {
      Navigator.push(context, MaterialPageRoute(builder: (c) => SearchPage(db: _db!, allBooks: _allBooks, currentBookNum: _currentBookNum))).then(_handleNavResult); 
    } else if (v == 'dictionary') {
      Navigator.push(context, MaterialPageRoute(builder: (c) => const KamusPage())); 
    } else if (v == 'offline_audio') {
      Navigator.push(context, MaterialPageRoute(builder: (c) => const OfflineAudioPage()));
    } else if (v == 'notes') {
      Navigator.push(context, MaterialPageRoute(builder: (c) => NoteListPage(prefs: _prefs, db: _db!, allBooks: _allBooks))).then((res) {
        _syncNotes(); // Tetap sinkronisasi
        // 👇 TANGKAP KOORDINAT LONCAT AYAT DARI DALAM CATATAN 👇
        if (res != null && res is Map) {
          _handleNavResult(res); 
        } else {
          setState(() {});
        }
      });
    }
  }

  void _handleNavResult(dynamic res) { if (res != null && res is Map) { setState(() { _currentBookNum = res['book_number']; _currentChapter = res['chapter']; }); _loadContent(scrollToVerse: res['verse']); } }
  void _goToNextChapter() { if (_currentChapter < (_chaptersPerBook[_currentBookNum >= 470 ? (((_currentBookNum - 470) ~/ 10) + 40) : (_currentBookNum ~/ 10)] ?? 1)) { _currentChapter++; } else { int idx = _allBooks.indexWhere((b) => b.bookNumber == _currentBookNum); if (idx < _allBooks.length - 1) { _currentBookNum = _allBooks[idx + 1].bookNumber; _currentChapter = 1; } } setState(() => _isLoading = true); _saveLastPosition(1); _loadContent(scrollToVerse: 1); }
  void _goToPrevChapter() { if (_currentChapter > 1) { _currentChapter--; } else { int idx = _allBooks.indexWhere((b) => b.bookNumber == _currentBookNum); if (idx > 0) { _currentBookNum = _allBooks[idx - 1].bookNumber; _currentChapter = _chaptersPerBook[(_currentBookNum ~/ 10)] ?? 1; } } setState(() => _isLoading = true); _saveLastPosition(1); _loadContent(scrollToVerse: 1); }
  void _showNavigation() { showGeneralDialog(context: context, barrierDismissible: true, barrierLabel: "Nav", pageBuilder: (c, a1, a2) => Align(alignment: Alignment.topCenter, child: Material(borderRadius: const BorderRadius.vertical(bottom: Radius.circular(25)), child: _NavSheet(allBooks: _allBooks, db: _db!, onSelectionComplete: (b, c, v) { Navigator.pop(context); setState(() { _currentBookNum = b; _currentChapter = c; }); _saveLastPosition(v); _loadContent(scrollToVerse: v); })))); }
  void _handleNoteClick(int vNum, List<String>? keys) { String bName = _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name; String ref = "$bName $_currentChapter:$vNum"; if (keys == null || keys.isEmpty) { Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: ref, prefs: _prefs, db: _db!, allBooks: _allBooks))).then(_handleNavResult); } else if (keys.length == 1) { _openNote(keys.first); } else { showModalBottomSheet(context: context, builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [ Padding(padding: const EdgeInsets.all(16), child: Text("Pilih Catatan ($ref)", style: const TextStyle(fontWeight: FontWeight.bold))), ...keys.map((k) => ListTile(leading: const Icon(Icons.note, color: Colors.orange), title: Text(_prefs.getString(k)?.split("~|~")[1].characters.take(30).toString() ?? ""), onTap: () { Navigator.pop(c); _openNote(k); })) ])); } }
  void _openNote(String k) { String? raw = _prefs.getString(k); if (raw != null) Navigator.push(context, MaterialPageRoute(builder: (c) => NoteEditorPage(nas: raw.split("~|~")[0], prefs: _prefs, existingKey: k, db: _db!, allBooks: _allBooks))).then(_handleNavResult); }
  
  List<InlineSpan> _parseTextWithLinks(String t) { List<InlineSpan> s = []; final r = RegExp(r'<x>(.*?)</x>'); int last = 0; for (var m in r.allMatches(t)) { if (m.start > last) s.add(TextSpan(text: _cleanText(t.substring(last, m.start)))); String it = m.group(1) ?? ""; try { List<String> p = it.split(RegExp(r'\s+')); int tb = int.parse(p[0]); String tr = p.length > 1 ? p.sublist(1).join(' ') : ""; BibleBook? b; try { b = _allBooks.firstWhere((x) => x.bookNumber == tb); } catch(e){} int tc = 1, tv = 1; if (tr.contains(':')) { var rp = tr.split(':'); tc = int.tryParse(rp[0]) ?? 1; tv = int.tryParse(rp[1].split(RegExp(r'[^0-9]')).first) ?? 1; } s.add(TextSpan(text: b != null ? "${b.shortName} $tr" : it, style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline, fontWeight: FontWeight.bold), recognizer: TapGestureRecognizer()..onTap = () { setState(() { _currentBookNum = tb; _currentChapter = tc; }); _saveLastPosition(tv); _loadContent(scrollToVerse: tv); })); } catch (e) { s.add(TextSpan(text: _cleanText(it))); } last = m.end; } if (last < t.length) s.add(TextSpan(text: _cleanText(t.substring(last)))); return s; }
  
  final Map<int, int> _chaptersPerBook = { 1: 50, 2: 40, 3: 27, 4: 36, 5: 34, 6: 24, 7: 21, 8: 4, 9: 31, 10: 24, 11: 22, 12: 25, 13: 29, 14: 36, 15: 10, 16: 13, 17: 10, 18: 42, 19: 150, 20: 31, 21: 12, 22: 8, 23: 66, 24: 52, 25: 5, 26: 48, 27: 12, 28: 14, 29: 3, 30: 9, 31: 1, 32: 4, 33: 7, 34: 3, 35: 3, 36: 3, 37: 2, 38: 14, 39: 4, 40: 28, 41: 16, 42: 24, 43: 21, 44: 28, 45: 16, 46: 16, 47: 13, 48: 6, 49: 6, 50: 4, 51: 4, 52: 5, 53: 3, 54: 6, 55: 4, 56: 3, 57: 1, 58: 13, 59: 5, 60: 5, 61: 3, 62: 5, 63: 1, 64: 1, 65: 1, 66: 22 };
  
  Future<void> _playPauseAudio() async { 
    int standardBookNum = 0;
    if (_currentBookNum >= 470) {
      standardBookNum = (((_currentBookNum - 470) ~/ 10) + 40);
    } else {
      Map<int, int> otTranslator = { 10: 1, 20: 2, 30: 3, 40: 4, 50: 5, 60: 6, 70: 7, 80: 8, 90: 9, 100: 10, 110: 11, 120: 12, 130: 13, 140: 14, 150: 15, 160: 16, 190: 17, 220: 18, 230: 19, 240: 20, 250: 21, 260: 22, 290: 23, 300: 24, 310: 25, 330: 26, 340: 27, 350: 28, 360: 29, 370: 30, 380: 31, 390: 32, 400: 33, 410: 34, 420: 35, 430: 36, 440: 37, 450: 38, 460: 39 };
      standardBookNum = otTranslator[_currentBookNum] ?? (_currentBookNum ~/ 10);
    }

    if (!_bibleAudioMap.containsKey(standardBookNum)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Audio belum tersedia."))); return; }
    String folder = _bibleAudioMap[standardBookNum]!["folder"]!;
    String prefix = _bibleAudioMap[standardBookNum]!["file"]!;
    String chapterStr = (folder == "mazmur") ? _currentChapter.toString().padLeft(3, '0') : _currentChapter.toString().padLeft(2, '0');
    String fileName = "$prefix$chapterStr.mp3";

    try {
      if (_isPlaying) { await _audioPlayer.pause(); } else {
        setState(() => _isAudioLoading = true);
        await _audioPlayer.setAudioContext(const AudioContext(android: AudioContextAndroid(isSpeakerphoneOn: true, stayAwake: true, contentType: AndroidContentType.music, usageType: AndroidUsageType.media, audioFocus: AndroidAudioFocus.gain), iOS: AudioContextIOS(category: AVAudioSessionCategory.playback, options: [AVAudioSessionOptions.defaultToSpeaker, AVAudioSessionOptions.mixWithOthers])));
        final dir = await getApplicationDocumentsDirectory();
        File localFile = File('${dir.path}/audio/$folder/$fileName');
        Source audioSource;
        if (await localFile.exists()) { audioSource = DeviceFileSource(localFile.path); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Memutar audio offline 🎧"))); } else { String onlineUrl = "https://raw.githubusercontent.com/pulicarpus/gereja_mobile/master/audio/$folder/$fileName"; audioSource = UrlSource(onlineUrl); }
        await _audioPlayer.play(audioSource);
        setState(() => _isAudioLoading = false);
      }
    } catch (e) { setState(() => _isAudioLoading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal memutar audio: $e"))); }
  }

  @override
  Widget build(BuildContext context) {
    String bName = _allBooks.isEmpty ? "" : _allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Row(children: [
          IconButton(icon: const Icon(Icons.chevron_left, size: 32), onPressed: _goToPrevChapter),
          Flexible(child: InkWell(onTap: _showNavigation, child: Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: Text("$bName $_currentChapter", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18), overflow: TextOverflow.ellipsis)), const Icon(Icons.arrow_drop_down)]))),
          IconButton(icon: const Icon(Icons.chevron_right, size: 32), onPressed: _goToNextChapter),
        ]),
        actions: [
          IconButton(icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.orange, size: 28), onPressed: _playPauseAudio),
          PopupMenuButton<String>(icon: const Icon(Icons.menu), onSelected: _onMenuSelected, itemBuilder: (c) => [
            const PopupMenuItem(value: 'search', child: Row(children: [Icon(Icons.search, color: Colors.indigo), SizedBox(width: 10), Text("Pencarian")])),
            const PopupMenuItem(value: 'dictionary', child: Row(children: [Icon(Icons.menu_book, color: Colors.orange), SizedBox(width: 10), Text("Kamus Alkitab")])),
            const PopupMenuItem(value: 'offline_audio', child: Row(children: [Icon(Icons.download, color: Colors.blue), SizedBox(width: 10), Text("Audio Offline")])),
            const PopupMenuItem(value: 'notes', child: Row(children: [Icon(Icons.edit_note, color: Colors.green), SizedBox(width: 10), Text("Kelola Catatan")])),
          ]),
        ],
        // 👇 AUDIO SLIDER TIPIS ELEGAN TEPAT DI BAWAH APPBAR 👇
        bottom: (_isPlaying || _isAudioLoading || _position > Duration.zero) 
          ? PreferredSize(
              preferredSize: const Size.fromHeight(30),
              child: Container(
                height: 30,
                color: Colors.indigo[800], 
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    _isAudioLoading 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2))
                      : InkWell(onTap: _playPauseAudio, child: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.orange, size: 22)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5), overlayShape: const RoundSliderOverlayShape(overlayRadius: 10)),
                        child: Slider(
                          activeColor: Colors.orange, inactiveColor: Colors.white30,
                          min: 0, max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1,
                          value: _position.inSeconds.toDouble().clamp(0, _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1),
                          onChanged: (val) => _audioPlayer.seek(Duration(seconds: val.toInt())),
                        ),
                      ),
                    ),
                    Text("${_position.inMinutes}:${(_position.inSeconds % 60).toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.white, fontSize: 10)),
                    const SizedBox(width: 8),
                    InkWell(onTap: () { _audioPlayer.stop(); setState(() { _isPlaying = false; _position = Duration.zero; }); }, child: const Icon(Icons.close, color: Colors.white54, size: 16))
                  ],
                )
              )
            )
          : null,
      ),
      
      body: _isLoading ? LoadingSultan(size: 80) : Listener(
        onPointerDown: (event) {
          _pointerPositions[event.pointer] = event.position;
          if (_pointerPositions.length == 2) {
            var pos = _pointerPositions.values.toList();
            _initialPinchDistance = (pos[0] - pos[1]).distance;
            _initialFontSize = _fontSize;
          }
        },
        onPointerMove: (event) {
          if (_pointerPositions.containsKey(event.pointer)) { _pointerPositions[event.pointer] = event.position; }
          if (_pointerPositions.length == 2) {
            var pos = _pointerPositions.values.toList();
            double scale = ((pos[0] - pos[1]).distance) / _initialPinchDistance;
            setState(() { _fontSize = (_initialFontSize * scale).clamp(12.0, 45.0); });
          }
        },
        onPointerUp: (event) { _pointerPositions.remove(event.pointer); if (_pointerPositions.isEmpty) _prefs.setDouble('LAST_FONT_SIZE', _fontSize); },
        onPointerCancel: (event) { _pointerPositions.remove(event.pointer); },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            int sensitivity = 300; 
            if (details.primaryVelocity! < -sensitivity) { _goToNextChapter(); } else if (details.primaryVelocity! > sensitivity) { _goToPrevChapter(); }
          },
          child: ListView(
            controller: _scrollController, 
            padding: const EdgeInsets.all(15),
            children: [ Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _buildContent())) ],
          ),
        ),
      ),
    ); 
  }

  List<Widget> _buildContent() {
    List<Widget> content = [];
    for (var v in _verses) {
      int vNum = v['verse'] as int; 
      bool isSel = _selectedVerses.contains(vNum);
      bool isHighlighted = (_highlightedVerse == vNum);
      
      String key = "${_currentBookNum}_${_currentChapter}_$vNum";
      Map<String, dynamic>? highlightData = _highlights[key];
      Color? stabiloColor = highlightData != null ? Color(highlightData['color']) : null;
      String? labelText = highlightData?['label'];
      
      bool hasNote = _verseNotesMap.containsKey(vNum) && _verseNotesMap[vNum]!.isNotEmpty;

      if (_perikopMap.containsKey(vNum)) { for (var t in _perikopMap[vNum]!) { content.add(Container(width: double.infinity, padding: const EdgeInsets.only(top: 25, bottom: 10), child: RichText(textAlign: TextAlign.center, text: TextSpan(style: TextStyle(fontWeight: FontWeight.bold, fontSize: _fontSize + 2, color: Colors.indigo.shade900), children: _parseTextWithLinks(t))))); } }
      
      content.add(GestureDetector(
        onLongPress: () { if (!isSel) setState(() => _selectedVerses.add(vNum)); _showActionMenu(); },
        onTap: () { setState(() { isSel ? _selectedVerses.remove(vNum) : _selectedVerses.add(vNum); _saveLastPosition(vNum); }); },
        child: Container(
          key: isHighlighted ? _targetVerseKey : null,
          color: isSel ? Colors.blue.withOpacity(0.2) : (stabiloColor ?? (isHighlighted ? Colors.yellow.withOpacity(0.4) : Colors.transparent)), 
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(text: TextSpan(style: TextStyle(color: Colors.black87, fontSize: _fontSize, height: 1.6), children: [
                TextSpan(text: "$vNum. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)), ..._parseTextWithLinks(v['text'].toString()),
              ])),
              if (labelText != null && labelText.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4, left: 20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(labelText, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo)))),
              if (hasNote)
                GestureDetector(
                  onTap: () => _handleNoteClick(vNum, _verseNotesMap[vNum]), 
                  child: Padding(padding: const EdgeInsets.only(top: 8.0, left: 20.0), child: Row(children: [Icon(Icons.edit_document, color: Colors.green.shade700, size: _fontSize * 0.9), const SizedBox(width: 5), Text("Lihat Catatan (${_verseNotesMap[vNum]!.length})", style: TextStyle(color: Colors.green.shade700, fontSize: _fontSize * 0.7, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic))] ))
                )
            ],
          ),
        ),
      ));
    }
    return content;
  }
}

class _NavSheet extends StatefulWidget { final List<BibleBook> allBooks; final Database db; final Function(int, int, int) onSelectionComplete; const _NavSheet({required this.allBooks, required this.db, required this.onSelectionComplete}); @override State<_NavSheet> createState() => _NavSheetState(); }
class _NavSheetState extends State<_NavSheet> { BibleBook? selB; int? selC; List<int> chs = []; List<int> vrs = []; void _getChapters(BibleBook b) async { final res = await widget.db.rawQuery("SELECT DISTINCT chapter FROM verses WHERE book_number = ? ORDER BY chapter ASC", [b.bookNumber]); setState(() { selB = b; chs = res.map((e) => e['chapter'] as int).toList(); selC = null; }); } void _getVerses(int c) async { final res = await widget.db.rawQuery("SELECT verse FROM verses WHERE book_number = ? AND chapter = ? ORDER BY verse ASC", [selB!.bookNumber, c]); setState(() { selC = c; vrs = res.map((e) => e['verse'] as int).toList(); }); } @override Widget build(BuildContext context) => SafeArea(child: Container(constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8), child: Column(mainAxisSize: MainAxisSize.min, children: [ AppBar(backgroundColor: Colors.transparent, elevation: 0, foregroundColor: Colors.black, title: Text(selB == null ? "Pilih Kitab" : (selC == null ? selB!.name : "${selB!.name} $selC")), leading: selB != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => selC != null ? selC = null : selB = null)) : null), const Divider(height: 1), Expanded(child: _buildGrid()) ]))); Widget _buildGrid() { if (selC != null) return _grid(vrs, (v) => widget.onSelectionComplete(selB!.bookNumber, selC!, v)); if (selB != null) return _grid(chs, (c) => _getVerses(c)); List<BibleBook> pl = widget.allBooks.length >= 39 ? widget.allBooks.sublist(0, 39) : widget.allBooks; List<BibleBook> pb = widget.allBooks.length > 39 ? widget.allBooks.sublist(39) : []; return ListView(children: [ _header("PERJANJIAN LAMA", Colors.pink), _kGrid(pl), if (pb.isNotEmpty) _header("PERJANJIAN BARU", Colors.blue), if (pb.isNotEmpty) _kGrid(pb) ]); } Widget _header(String t, Color c) => Padding(padding: const EdgeInsets.all(15), child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold))); Widget _kGrid(List<BibleBook> bks) => GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 10), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 70, childAspectRatio: 2, mainAxisSpacing: 5, crossAxisSpacing: 5), itemCount: bks.length, itemBuilder: (c, i) => InkWell(onTap: () => _getChapters(bks[i]), child: Container(alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(5)), child: Text(bks[i].shortName.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))))); Widget _grid(List<int> its, Function(int) onTap) => GridView.builder(padding: const EdgeInsets.all(15), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 60, mainAxisSpacing: 10, crossAxisSpacing: 10), itemCount: its.length, itemBuilder: (c, i) => InkWell(onTap: () => onTap(its[i]), child: Container(alignment: Alignment.center, decoration: BoxDecoration(color: Colors.indigo[50], borderRadius: BorderRadius.circular(10)), child: Text("${its[i]}", style: const TextStyle(fontWeight: FontWeight.bold))))); }