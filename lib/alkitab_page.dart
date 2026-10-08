import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'bible_models.dart';
import 'bible_support.dart';
import 'bible_local_store.dart';
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
  late SharedPreferences _prefs;

  double _fontSize = 18.0;
  Map<int, Offset> _pointerPositions = {};
  double _initialPinchDistance = 0.0;
  double _initialFontSize = 18.0;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isAudioLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  late BibleLocalStore _store;
  String? _loadError;
  int _contentRequest = 0;
  Timer? _highlightTimer;
  final List<TapGestureRecognizer> _recognizers = [];
  final List<StreamSubscription<dynamic>> _audioSubscriptions = [];
  String? _audioIdentity;
  bool _audioPaused = false;
  String? _audioLabel;
  String _positionKey(String name) =>
      'BIBLE_POSITION_${_store.uid ?? "guest"}_$name';

  @override
  void initState() {
    super.initState();
    _initApp();
    _setupAudioListeners();
  }

  void _setupAudioListeners() {
    _audioSubscriptions.add(
      _audioPlayer.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        setState(() {
          _isPlaying = state == PlayerState.playing;
          _audioPaused = state == PlayerState.paused;
        });
      }),
    );
    _audioSubscriptions.add(
      _audioPlayer.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
    );
    _audioSubscriptions.add(
      _audioPlayer.onPositionChanged.listen((value) {
        if (mounted) setState(() => _position = value);
      }),
    );
    _audioSubscriptions.add(
      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted)
          setState(() {
            _isPlaying = false;
            _audioPaused = false;
            _audioIdentity = null;
            _position = Duration.zero;
          });
      }),
    );
  }

  @override
  void dispose() {
    _contentRequest++;
    _highlightTimer?.cancel();
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    for (final subscription in _audioSubscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_audioPlayer.dispose());
    unawaited(_db?.close());
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initApp() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _store = BibleLocalStore(_prefs, FirebaseAuth.instance.currentUser?.uid);
      _currentBookNum =
          _prefs.getInt(_positionKey('book')) ??
          _prefs.getInt('LAST_BOOK_NUM') ??
          10;
      _currentChapter =
          _prefs.getInt(_positionKey('chapter')) ??
          _prefs.getInt('LAST_CHAPTER') ??
          1;
      _currentVerse =
          _prefs.getInt(_positionKey('verse')) ??
          _prefs.getInt('LAST_VERSE') ??
          1;
      try {
        final saved = jsonDecode(
          _prefs.getString(_positionKey('position')) ?? 'null',
        );
        if (saved is Map &&
            saved['book'] is int &&
            saved['chapter'] is int &&
            saved['verse'] is int) {
          _currentBookNum = saved['book'];
          _currentChapter = saved['chapter'];
          _currentVerse = saved['verse'];
        }
      } catch (_) {
        /* Posisi lama masih dapat dibaca. */
      }
      final savedSize = _prefs.getDouble('LAST_FONT_SIZE') ?? 18.0;
      _fontSize = savedSize.isFinite ? savedSize.clamp(12.0, 45.0) : 18.0;
      _highlights = _store.loadHighlights();
      await _loadDatabase();
    } catch (_) {
      if (mounted)
        setState(() {
          _isLoading = false;
          _loadError = 'Tidak dapat memuat Alkitab. Silakan coba lagi.';
        });
    }
  }

  Future<void> _saveLastPosition(int verse) async {
    _currentVerse = verse;
    await _prefs.setString(
      _positionKey('position'),
      jsonEncode({
        'book': _currentBookNum,
        'chapter': _currentChapter,
        'verse': verse,
      }),
    );
  }

  Future<void> _saveHighlightsToPrefs() async {
    try {
      await _store.saveHighlights(_highlights);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stabilo belum tersimpan. Coba lagi.')),
        );
    }
  }

  Future<void> _loadDatabase() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      await _db?.close();
      _db = null;
      final dbPath = await getDatabasesPath();
      await Directory(dbPath).create(recursive: true);
      final path = p.join(dbPath, _currentVersion);
      for (var attempt = 0; attempt < 2; attempt++) {
        Database? opened;
        try {
          if (!await databaseExists(path)) {
            final data = await rootBundle.load('assets/$_currentVersion');
            final temp = File('$path.part');
            await temp.writeAsBytes(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              flush: true,
            );
            await temp.rename(path);
          }
          opened = await openDatabase(
            path,
            readOnly: true,
            singleInstance: false,
          );
          final check = await opened.rawQuery('PRAGMA quick_check');
          if (check.isEmpty || check.first.values.first != 'ok') {
            throw StateError('Database tidak valid.');
          }
          final rows = await opened.query('books', orderBy: 'book_number ASC');
          if (rows.isEmpty) throw StateError('Daftar kitab kosong.');
          if (!mounted) {
            await opened.close();
            return;
          }
          _db = opened;
          _allBooks = rows
              .map(
                (e) => BibleBook(
                  bookNumber: e['book_number'] as int,
                  name: e['long_name'].toString(),
                  shortName: e['short_name'].toString(),
                ),
              )
              .toList();
          break;
        } catch (_) {
          await opened?.close();
          if (attempt == 1) rethrow;
          if (await File(path).exists()) await File(path).delete();
        }
      }
      if (!_allBooks.any((b) => b.bookNumber == _currentBookNum)) {
        _currentBookNum = _allBooks.first.bookNumber;
        _currentChapter = 1;
        _currentVerse = 1;
      }
      final chapters = await _db!.rawQuery(
        'SELECT DISTINCT chapter FROM verses WHERE book_number = ? ORDER BY chapter',
        [_currentBookNum],
      );
      if (!chapters.any((row) => row['chapter'] == _currentChapter)) {
        _currentChapter = chapters.first['chapter'] as int;
        _currentVerse = 1;
      }
      await _loadContent(scrollToVerse: _currentVerse);
    } catch (_) {
      if (mounted)
        setState(() {
          _isLoading = false;
          _loadError = 'Database Alkitab tidak dapat dibuka. Coba lagi.';
        });
    }
  }

  Future<void> _stopAudio() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio belum dapat dihentikan. Coba lagi.'),
          ),
        );
      return;
    }
    if (!mounted) return;
    setState(() {
      _audioIdentity = null;
      _audioPaused = false;
      _audioLabel = null;
      _isPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
  }

  Future<void> _loadContent({
    int? bookId,
    int? chapter,
    int? scrollToVerse,
  }) async {
    if (!mounted) return;
    final request = ++_contentRequest;
    final targetBook = bookId ?? _currentBookNum;
    final targetChapter = chapter ?? _currentChapter;
    final db = _db;
    _highlightTimer?.cancel();
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      if (db == null || !_allBooks.any((b) => b.bookNumber == targetBook)) {
        throw StateError('Kitab tidak tersedia.');
      }
      if (_audioIdentity != null &&
          _audioIdentity != '$targetBook:$targetChapter')
        await _stopAudio();
      final rows = await db.query(
        'verses',
        where: 'book_number = ? AND chapter = ?',
        whereArgs: [targetBook, targetChapter],
        orderBy: 'verse ASC',
      );
      if (rows.isEmpty) throw StateError('Pasal tidak tersedia.');
      List<Map<String, dynamic>> stories = [];
      try {
        stories = await db.query(
          'stories',
          where: 'book_number = ? AND chapter = ?',
          whereArgs: [targetBook, targetChapter],
          orderBy: 'verse ASC, order_if_several ASC',
        );
      } on DatabaseException {
        /* Versi tanpa perikop tetap dapat dibaca. */
      }
      if (!mounted || request != _contentRequest) return;
      final titles = <int, List<String>>{};
      for (final row in stories) {
        titles
            .putIfAbsent(row['verse'] as int, () => [])
            .add(row['title'].toString());
      }
      final targetVerse = rows.any((r) => r['verse'] == scrollToVerse)
          ? scrollToVerse!
          : rows.first['verse'] as int;
      setState(() {
        _currentBookNum = targetBook;
        _currentChapter = targetChapter;
        _verses = rows;
        _perikopMap = titles;
        _selectedVerses.clear();
        _pointerPositions.clear();
        _highlightedVerse = targetVerse;
        _syncNotes();
      });
      await _saveLastPosition(targetVerse);
      if (!mounted || request != _contentRequest) return;
      setState(() => _isLoading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || request != _contentRequest) return;
        final target = _targetVerseKey.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 300),
            alignment: 0.3,
          );
        }
      });
      _highlightTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && request == _contentRequest) {
          setState(() => _highlightedVerse = null);
        }
      });
    } catch (_) {
      if (mounted && request == _contentRequest)
        setState(() {
          _isLoading = false;
          _loadError = 'Pasal tidak dapat dimuat. Silakan coba lagi.';
        });
    }
  }

  void _syncNotes() {
    _verseNotesMap.clear();
    for (final key in _store.noteKeys) {
      final raw = _store.readNote(key);
      if (raw == null) continue;
      final note = NoteModel.fromRaw(key, raw);
      final reference = BibleReference.parse(note.nas, _allBooks);
      if (reference == null ||
          reference.bookId != _currentBookNum ||
          reference.chapter != _currentChapter)
        continue;
      for (final verse in reference.verses) {
        _verseNotesMap.putIfAbsent(verse, () => []).add(key);
      }
    }
  }

  void _showActionMenu() {
    if (_selectedVerses.isEmpty) return;
    List<int> sorted = _selectedVerses.toList()..sort();
    String bName = _allBooks
        .firstWhere((b) => b.bookNumber == _currentBookNum)
        .name;
    String nas = "$bName $_currentChapter:${_formatVerses(sorted)}";

    showModalBottomSheet(
      context: context,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              nas,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text("Salin Ayat"),
            onTap: () {
              String txt = "$nas\n";
              for (var v in sorted) {
                var d = _verses.firstWhere((e) => e['verse'] == v);
                txt += "$v. ${_cleanText(d['text'])}\n";
              }
              Clipboard.setData(ClipboardData(text: txt));
              Navigator.pop(context);
              setState(() => _selectedVerses.clear());
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_comment, color: Colors.blue),
            title: const Text("Buat Catatan"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (c) => NoteEditorPage(
                    nas: nas,
                    prefs: _prefs,
                    db: _db!,
                    allBooks: _allBooks,
                  ),
                ),
              ).then(_handleNavResult);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_attributes, color: Colors.orange),
            title: const Text("Beri Stabilo & Label"),
            onTap: () {
              Navigator.pop(context);
              _showStabiloDialog(sorted);
            },
          ),
          ListTile(
            leading: const Icon(Icons.image, color: Colors.purple),
            title: const Text("Jadikan Gambar"),
            onTap: () {
              Navigator.pop(context);
              String txt = "";
              for (var v in sorted) {
                var d = _verses.firstWhere((e) => e['verse'] == v);
                txt += "${_cleanText(d['text'])} ";
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (c) =>
                      BuatGambarPage(ayatTeks: txt.trim(), referensi: nas),
                ),
              );
              setState(() => _selectedVerses.clear());
            },
          ),
        ],
      ),
    );
  }

  void _showStabiloDialog(List<int> verses) {
    String label = "";
    int colorValue = Colors.yellow.withOpacity(0.3).value;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Stabilo & Label"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Pilih Warna:"),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _colorCircle(Colors.yellow, (v) => colorValue = v),
                _colorCircle(Colors.greenAccent, (v) => colorValue = v),
                _colorCircle(Colors.lightBlueAccent, (v) => colorValue = v),
                _colorCircle(Colors.pinkAccent, (v) => colorValue = v),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              decoration: const InputDecoration(
                labelText: "Label (Cth: Kasih, Janji)",
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => label = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                for (var v in verses) {
                  _highlights.remove(
                    "${_currentBookNum}_${_currentChapter}_$v",
                  );
                }
              });
              _saveHighlightsToPrefs();
              Navigator.pop(c);
              setState(() => _selectedVerses.clear());
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                for (var v in verses) {
                  _highlights["${_currentBookNum}_${_currentChapter}_$v"] = {
                    "color": colorValue,
                    "label": label.trim(),
                  };
                }
              });
              _saveHighlightsToPrefs();
              Navigator.pop(c);
              setState(() => _selectedVerses.clear());
            },
            child: const Text("Simpan"),
          ),
        ],
      ),
    );
  }

  Widget _colorCircle(Color color, Function(int) onSelect) => InkWell(
    onTap: () => onSelect(color.withOpacity(0.3).value),
    child: CircleAvatar(backgroundColor: color, radius: 15),
  );
  String _cleanText(String text) => cleanBibleText(text);
  String _formatVerses(List<int> vs) {
    if (vs.isEmpty) return "";
    vs.sort();
    List<String> groups = [];
    int start = vs.first, end = vs.first;
    for (int i = 1; i < vs.length; i++) {
      if (vs[i] == end + 1) {
        end = vs[i];
      } else {
        groups.add(start == end ? "$start" : "$start-$end");
        start = vs[i];
        end = vs[i];
      }
    }
    groups.add(start == end ? "$start" : "$start-$end");
    return groups.join(", ");
  }

  Future<void> _onMenuSelected(String v) async {
    if (v == 'search') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (c) => SearchPage(
            db: _db!,
            allBooks: _allBooks,
            currentBookNum: _currentBookNum,
          ),
        ),
      ).then(_handleNavResult);
    } else if (v == 'dictionary') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (c) => KamusPage(allBooks: _allBooks)),
      ).then(_handleNavResult);
    } else if (v == 'offline_audio') {
      try {
        await _stopAudio();
      } catch (_) {
        return;
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (c) => const OfflineAudioPage()),
      );
    } else if (v == 'notes') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (c) =>
              NoteListPage(prefs: _prefs, db: _db!, allBooks: _allBooks),
        ),
      ).then(_handleNavResult);
    }
  }

  Future<void> _handleNavResult(dynamic result) async {
    if (!mounted) return;
    setState(() {
      _syncNotes();
      _highlights = _store.loadHighlights();
      _selectedVerses.clear();
    });
    if (result is Map &&
        result['book_number'] is int &&
        result['chapter'] is int &&
        result['verse'] is int) {
      await _loadContent(
        bookId: result['book_number'],
        chapter: result['chapter'],
        scrollToVerse: result['verse'],
      );
    }
  }

  Future<void> _stepChapter(bool forward) async {
    if (_isLoading || _loadError != null || _db == null) return;
    try {
      final index = _allBooks.indexWhere(
        (b) => b.bookNumber == _currentBookNum,
      );
      if (index < 0) return;
      final rows = await _db!.rawQuery(
        'SELECT DISTINCT chapter FROM verses WHERE book_number = ? ORDER BY chapter',
        [_currentBookNum],
      );
      if (!mounted || _isLoading) return;
      final chapters = rows.map((r) => r['chapter'] as int).toList();
      final current = chapters.indexOf(_currentChapter);
      final next = current + (forward ? 1 : -1);
      if (next >= 0 && next < chapters.length) {
        await _loadContent(chapter: chapters[next], scrollToVerse: 1);
      } else {
        final bookIndex = index + (forward ? 1 : -1);
        if (bookIndex < 0 || bookIndex >= _allBooks.length) return;
        final book = _allBooks[bookIndex].bookNumber;
        final adjacent = await _db!.rawQuery(
          'SELECT DISTINCT chapter FROM verses WHERE book_number = ? ORDER BY chapter',
          [book],
        );
        if (!mounted || adjacent.isEmpty) return;
        await _loadContent(
          bookId: book,
          chapter: (forward ? adjacent.first : adjacent.last)['chapter'] as int,
          scrollToVerse: 1,
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Navigasi gagal. Silakan coba lagi.')),
        );
    }
  }

  void _goToNextChapter() {
    _stepChapter(true);
  }

  void _goToPrevChapter() {
    _stepChapter(false);
  }

  void _showNavigation() {
    if (_isLoading || _db == null || _loadError != null) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Navigasi',
      pageBuilder: (dialogContext, a1, a2) => Align(
        alignment: Alignment.topCenter,
        child: Material(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(25),
          ),
          child: _NavSheet(
            allBooks: _allBooks,
            db: _db!,
            onSelectionComplete: (book, chapter, verse) {
              Navigator.pop(dialogContext);
              if (mounted)
                _loadContent(
                  bookId: book,
                  chapter: chapter,
                  scrollToVerse: verse,
                );
            },
          ),
        ),
      ),
    );
  }

  void _handleNoteClick(int verse, List<String>? keys) {
    if (keys == null || keys.isEmpty) return;
    if (keys.length == 1) {
      _openNote(keys.first);
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: keys
              .map(
                (key) => ListTile(
                  title: Text(
                    NoteModel.fromRaw(key, _store.readNote(key) ?? '').title,
                  ),
                  onTap: () {
                    Navigator.pop(c);
                    _openNote(key);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _openNote(String key) {
    final raw = _store.readNote(key);
    if (raw == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => NoteEditorPage(
          nas: NoteModel.fromRaw(key, raw).nas,
          prefs: _prefs,
          existingKey: key,
          db: _db!,
          allBooks: _allBooks,
        ),
      ),
    ).then(_handleNavResult);
  }

  List<InlineSpan> _parseTextWithLinks(String text) {
    final spans = <InlineSpan>[];
    final matches = RegExp(r'<x>(.*?)</x>').allMatches(text);
    var last = 0;
    for (final match in matches) {
      if (match.start > last) {
        spans.add(
          TextSpan(
            text: cleanBibleText(text.substring(last, match.start)) + ' ',
          ),
        );
      }
      final raw = match[1] ?? '';
      final ref = RegExp(r'^(\d+)\s+(\d+):(\d+)').firstMatch(raw.trim());
      BibleBook? book;
      if (ref != null) {
        final id = int.parse(ref[1]!);
        for (final item in _allBooks) {
          if (item.bookNumber == id) book = item;
        }
      }
      if (book == null || ref == null) {
        spans.add(TextSpan(text: raw));
      } else {
        final id = book.bookNumber;
        final chapter = int.parse(ref[2]!);
        final verse = int.parse(ref[3]!);
        final recognizer = TapGestureRecognizer()
          ..onTap = () {
            if (!_isLoading && !_isAudioLoading)
              _loadContent(bookId: id, chapter: chapter, scrollToVerse: verse);
          };
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: '${book.shortName} ${raw.substring(raw.indexOf(' ') + 1)}',
            style: const TextStyle(
              color: Colors.blue,
              decoration: TextDecoration.underline,
            ),
            recognizer: recognizer,
          ),
        );
      }
      last = match.end;
    }
    if (last < text.length)
      spans.add(TextSpan(text: ' ' + cleanBibleText(text.substring(last))));
    return spans;
  }

  Future<void> _playPauseAudio() async {
    if (_isLoading || _isAudioLoading || _loadError != null) return;
    final ordinal = bibleOrdinal(_currentBookNum);
    if (ordinal == null) return;
    final identity = '$_currentBookNum:$_currentChapter';
    final label =
        '${_allBooks.firstWhere((b) => b.bookNumber == _currentBookNum).name} $_currentChapter';
    setState(() => _isAudioLoading = true);
    try {
      if (_isPlaying && _audioIdentity == identity) {
        await _audioPlayer.pause();
      } else if (_audioPaused && _audioIdentity == identity) {
        await _audioPlayer.resume();
      } else {
        final relativePath = bibleAudioPath(ordinal, _currentChapter);
        final dir = await getApplicationDocumentsDirectory();
        final local = File('${dir.path}/audio/$relativePath');
        var offline = false;
        if (await local.exists() && await local.length() >= 3) {
          final file = await local.open();
          try {
            offline = isMp3Header(await file.read(3));
          } finally {
            await file.close();
          }
        }
        if (!mounted || identity != '$_currentBookNum:$_currentChapter') return;
        _audioIdentity = identity;
        _audioLabel = label;
        await _audioPlayer.play(
          offline
              ? DeviceFileSource(local.path)
              : UrlSource('$bibleAudioBaseUrl/$relativePath'),
        );
      }
    } catch (_) {
      if (mounted) {
        _audioIdentity = null;
        _audioLabel = null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Audio gagal dimuat. Periksa koneksi atau unduh ulang pasal.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAudioLoading = false);
    }
  }

  Future<void> _seekAudio(double seconds) async {
    if (_isAudioLoading || _duration == Duration.zero) return;
    try {
      await _audioPlayer.seek(Duration(seconds: seconds.toInt()));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Posisi audio belum dapat diubah.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    String bName = '';
    for (final book in _allBooks) {
      if (book.bookNumber == _currentBookNum) bName = book.name;
    }
    final ready =
        !_isLoading && !_isAudioLoading && _loadError == null && _db != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: Navigator.canPop(context)
            ? IconButton(
                tooltip: 'Kembali',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.maybePop(context),
              )
            : null,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 32),
              onPressed: ready && !_isAudioLoading ? _goToPrevChapter : null,
            ),
            Flexible(
              child: InkWell(
                onTap: ready && !_isAudioLoading ? _showNavigation : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        "$bName $_currentChapter",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 32),
              onPressed: ready && !_isAudioLoading ? _goToNextChapter : null,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              color: Colors.orange,
              size: 28,
            ),
            onPressed: ready && !_isAudioLoading ? _playPauseAudio : null,
          ),
          PopupMenuButton<String>(
            enabled: ready,
            icon: const Icon(Icons.menu),
            onSelected: _onMenuSelected,
            itemBuilder: (c) => [
              const PopupMenuItem(
                value: 'search',
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.indigo),
                    SizedBox(width: 10),
                    Text("Pencarian"),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'dictionary',
                child: Row(
                  children: [
                    Icon(Icons.menu_book, color: Colors.orange),
                    SizedBox(width: 10),
                    Text("Kamus Alkitab"),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'offline_audio',
                child: Row(
                  children: [
                    Icon(Icons.download, color: Colors.blue),
                    SizedBox(width: 10),
                    Text("Audio Offline"),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'notes',
                child: Row(
                  children: [
                    Icon(Icons.edit_note, color: Colors.green),
                    SizedBox(width: 10),
                    Text("Kelola Catatan"),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom:
            (_isPlaying ||
                _isAudioLoading ||
                _audioPaused ||
                _position > Duration.zero)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(30),
                child: Container(
                  height: 30,
                  color: Colors.indigo[800],
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      if (_audioLabel != null)
                        Tooltip(
                          message: _audioLabel!,
                          child: const Icon(
                            Icons.headphones,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      _isAudioLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.orange,
                                strokeWidth: 2,
                              ),
                            )
                          : InkWell(
                              onTap: _playPauseAudio,
                              child: Icon(
                                _isPlaying
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_fill,
                                color: Colors.orange,
                                size: 22,
                              ),
                            ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 10,
                            ),
                          ),
                          child: Slider(
                            activeColor: Colors.orange,
                            inactiveColor: Colors.white30,
                            min: 0,
                            max: _duration.inSeconds.toDouble() > 0
                                ? _duration.inSeconds.toDouble()
                                : 1,
                            value: _position.inSeconds.toDouble().clamp(
                              0,
                              _duration.inSeconds.toDouble() > 0
                                  ? _duration.inSeconds.toDouble()
                                  : 1,
                            ),
                            onChanged: _isAudioLoading ? null : _seekAudio,
                          ),
                        ),
                      ),
                      Text(
                        "${_position.inMinutes}:${(_position.inSeconds % 60).toString().padLeft(2, '0')}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _isAudioLoading ? null : _stopAudio,
                        child: const Icon(
                          Icons.close,
                          color: Colors.white54,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),

      body: _isLoading
          ? LoadingSultan(size: 80)
          : _loadError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: _initApp,
                    child: const Text('Coba lagi'),
                  ),
                ],
              ),
            )
          : Listener(
              onPointerDown: (event) {
                _pointerPositions[event.pointer] = event.position;
                if (_pointerPositions.length == 2) {
                  var pos = _pointerPositions.values.toList();
                  _initialPinchDistance = (pos[0] - pos[1]).distance;
                  _initialFontSize = _fontSize;
                }
              },
              onPointerMove: (event) {
                if (_pointerPositions.containsKey(event.pointer)) {
                  _pointerPositions[event.pointer] = event.position;
                }
                if (_pointerPositions.length == 2 &&
                    _initialPinchDistance > 0) {
                  var pos = _pointerPositions.values.toList();
                  double scale =
                      ((pos[0] - pos[1]).distance) / _initialPinchDistance;
                  setState(() {
                    _fontSize = (_initialFontSize * scale).clamp(12.0, 45.0);
                  });
                }
              },
              onPointerUp: (event) {
                _pointerPositions.remove(event.pointer);
                if (_pointerPositions.isEmpty)
                  _prefs.setDouble('LAST_FONT_SIZE', _fontSize);
              },
              onPointerCancel: (event) {
                _pointerPositions.remove(event.pointer);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (details) {
                  if (_isAudioLoading) return;
                  int sensitivity = 300;
                  if ((details.primaryVelocity ?? 0) < -sensitivity) {
                    _goToNextChapter();
                  } else if ((details.primaryVelocity ?? 0) > sensitivity) {
                    _goToPrevChapter();
                  }
                },
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(15),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _buildContent(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _buildContent() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    List<Widget> content = [];
    for (var v in _verses) {
      int vNum = v['verse'] as int;
      bool isSel = _selectedVerses.contains(vNum);
      bool isHighlighted = (_highlightedVerse == vNum);

      String key = "${_currentBookNum}_${_currentChapter}_$vNum";
      Map<String, dynamic>? highlightData = _highlights[key];
      Color? stabiloColor = highlightData != null
          ? Color(highlightData['color'])
          : null;
      String? labelText = highlightData?['label'];

      bool hasNote =
          _verseNotesMap.containsKey(vNum) && _verseNotesMap[vNum]!.isNotEmpty;

      if (_perikopMap.containsKey(vNum)) {
        for (var t in _perikopMap[vNum]!) {
          content.add(
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 25, bottom: 10),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: _fontSize + 2,
                    color: Colors.indigo.shade900,
                  ),
                  children: _parseTextWithLinks(t),
                ),
              ),
            ),
          );
        }
      }

      content.add(
        GestureDetector(
          onLongPress: () {
            if (!isSel) setState(() => _selectedVerses.add(vNum));
            _showActionMenu();
          },
          onTap: () {
            setState(() {
              isSel ? _selectedVerses.remove(vNum) : _selectedVerses.add(vNum);
              _saveLastPosition(vNum).catchError((Object _) {});
            });
          },
          child: Container(
            key: isHighlighted ? _targetVerseKey : null,
            color: isSel
                ? Colors.blue.withOpacity(0.2)
                : (stabiloColor ??
                      (isHighlighted
                          ? Colors.yellow.withOpacity(0.4)
                          : Colors.transparent)),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: _fontSize,
                      height: 1.6,
                    ),
                    children: [
                      TextSpan(
                        text: "$vNum. ",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      ..._parseTextWithLinks(v['text'].toString()),
                    ],
                  ),
                ),
                if (labelText != null && labelText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        labelText,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                    ),
                  ),
                if (hasNote)
                  GestureDetector(
                    onTap: () => _handleNoteClick(vNum, _verseNotesMap[vNum]),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 20.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_document,
                            color: Colors.green.shade700,
                            size: _fontSize * 0.9,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            "Lihat Catatan (${_verseNotesMap[vNum]!.length})",
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: _fontSize * 0.7,
                              fontWeight: FontWeight.bold,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return content;
  }
}

class _NavSheet extends StatefulWidget {
  final List<BibleBook> allBooks;
  final Database db;
  final Function(int, int, int) onSelectionComplete;
  const _NavSheet({
    required this.allBooks,
    required this.db,
    required this.onSelectionComplete,
  });
  @override
  State<_NavSheet> createState() => _NavSheetState();
}

class _NavSheetState extends State<_NavSheet> {
  BibleBook? selB;
  int? selC;
  List<int> chs = [], vrs = [];
  bool loading = false;
  String? error;
  int request = 0;
  @override
  void dispose() {
    request++;
    super.dispose();
  }

  Future<void> _getChapters(BibleBook book) async {
    final token = ++request;
    setState(() {
      selB = book;
      selC = null;
      chs = [];
      vrs = [];
      loading = true;
      error = null;
    });
    try {
      final rows = await widget.db.rawQuery(
        'SELECT DISTINCT chapter FROM verses WHERE book_number = ? ORDER BY chapter',
        [book.bookNumber],
      );
      if (!mounted || token != request) return;
      setState(() => chs = rows.map((r) => r['chapter'] as int).toList());
    } catch (_) {
      if (mounted && token == request)
        setState(() => error = 'Pasal gagal dimuat.');
    } finally {
      if (mounted && token == request) setState(() => loading = false);
    }
  }

  Future<void> _getVerses(int chapter) async {
    final book = selB;
    if (book == null) return;
    final token = ++request;
    setState(() {
      selC = chapter;
      vrs = [];
      loading = true;
      error = null;
    });
    try {
      final rows = await widget.db.rawQuery(
        'SELECT verse FROM verses WHERE book_number = ? AND chapter = ? ORDER BY verse',
        [book.bookNumber, chapter],
      );
      if (!mounted || token != request) return;
      setState(() => vrs = rows.map((r) => r['verse'] as int).toList());
    } catch (_) {
      if (mounted && token == request)
        setState(() => error = 'Ayat gagal dimuat.');
    } finally {
      if (mounted && token == request) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: Colors.black,
            title: Text(
              selB == null
                  ? 'Pilih Kitab'
                  : selC == null
                  ? selB!.name
                  : '${selB!.name} $selC',
            ),
            leading: selB == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() {
                      request++;
                      loading = false;
                      error = null;
                      if (selC != null) {
                        selC = null;
                      } else {
                        selB = null;
                      }
                    }),
                  ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(child: Text(error!))
                : _buildGrid(),
          ),
        ],
      ),
    ),
  );

  Widget _buildGrid() {
    if (selC != null)
      return _grid(
        vrs,
        (v) => widget.onSelectionComplete(selB!.bookNumber, selC!, v),
      );
    if (selB != null) return _grid(chs, _getVerses);
    final pl = widget.allBooks
        .where((b) => isOldTestament(b.bookNumber))
        .toList();
    final pb = widget.allBooks
        .where((b) => !isOldTestament(b.bookNumber))
        .toList();
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(15),
          child: Text('PERJANJIAN LAMA'),
        ),
        _books(pl),
        const Padding(
          padding: EdgeInsets.all(15),
          child: Text('PERJANJIAN BARU'),
        ),
        _books(pb),
      ],
    );
  }

  Widget _books(List<BibleBook> books) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.all(10),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 80,
      childAspectRatio: 2,
      mainAxisSpacing: 5,
      crossAxisSpacing: 5,
    ),
    itemCount: books.length,
    itemBuilder: (c, i) => OutlinedButton(
      onPressed: () => _getChapters(books[i]),
      child: Text(books[i].shortName, style: const TextStyle(fontSize: 11)),
    ),
  );

  Widget _grid(List<int> values, void Function(int) onTap) => GridView.builder(
    padding: const EdgeInsets.all(15),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 60,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
    ),
    itemCount: values.length,
    itemBuilder: (c, i) => OutlinedButton(
      onPressed: () => onTap(values[i]),
      child: Text('${values[i]}'),
    ),
  );
}
