import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'bible_models.dart';
import 'bible_support.dart';
import 'sermon_document.dart';
import 'sermon_paragraph.dart';
import 'sermon_references.dart';

class SermonPage extends StatefulWidget {
  final NoteModel note;
  final Database db;
  final List<BibleBook> books;
  final SharedPreferences? prefs;
  final String? ownerUid;
  final bool manageDevice;
  const SermonPage({
    super.key,
    required this.note,
    required this.db,
    required this.books,
    this.prefs,
    this.ownerUid,
    this.manageDevice = true,
  });
  @override
  State<SermonPage> createState() => _SermonPageState();
}

class _SermonPageState extends State<SermonPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _clock = Stopwatch();
  late final Ticker _ticker;
  Timer? _clockUpdate;
  Duration? _lastFrame;
  late final List<SermonParagraph> _paragraphs;
  late final List<GlobalKey> _anchors;
  late final SermonParagraph _referenceParagraph;
  late final SermonReferenceMatcher _matcher;
  late final Future<void> _deviceReady;
  bool _auto = false, _overlay = false, _controls = true, _active = true;
  bool? _previousWake, _previousFullscreen;
  bool _wakeFailed = false, _resumeClock = false;
  double _font = 24, _speed = 20, _lastOffset = 0;
  String _theme = 'light';
  String get _positionKey =>
      'SERMON_${Uri.encodeComponent(widget.ownerUid ?? 'guest')}_${Uri.encodeComponent(widget.note.key)}_scroll';
  bool get _dark => _theme == 'dark';
  Color get _background => _dark
      ? const Color(0xFF14171C)
      : _theme == 'sepia'
      ? const Color(0xFFF7EEDB)
      : Colors.white;
  Color get _foreground =>
      _dark ? const Color(0xFFF1F3F5) : const Color(0xFF20252C);
  Color get _link => _dark ? Colors.lightBlueAccent : Colors.blue.shade800;
  String get _elapsed {
    final value = _clock.elapsed;
    return '${value.inMinutes.toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _paragraphs = sermonParagraphs(widget.note);
    _anchors = List.generate(_paragraphs.length, (_) => GlobalKey());
    _matcher = SermonReferenceMatcher(widget.books);
    _referenceParagraph = SermonParagraph(
      [SermonRun(widget.note.nas, const {})],
      const {},
      null,
    );
    final font = widget.prefs?.getDouble('SERMON_font') ?? 24;
    final speed = widget.prefs?.getDouble('SERMON_speed') ?? 20;
    _font = font.isFinite ? font.clamp(16.0, 42.0) : 24;
    _speed = speed.isFinite ? speed.clamp(5.0, 80.0) : 20;
    final theme = widget.prefs?.getString('SERMON_theme');
    _theme = ['light', 'sepia', 'dark'].contains(theme) ? theme! : 'light';
    _ticker = createTicker(_tick);
    _clock.start();
    _clockUpdate = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _scroll.addListener(() => _lastOffset = _scroll.offset);
    _deviceReady = widget.manageDevice ? _enterDeviceMode() : Future.value();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final saved = widget.prefs?.getDouble(_positionKey);
      if (mounted && _scroll.hasClients && saved != null && saved.isFinite) {
        _scroll.jumpTo(saved.clamp(0.0, _scroll.position.maxScrollExtent));
      }
    });
  }

  Future<void> _enterDeviceMode() async {
    try {
      _previousWake = await WakelockPlus.enabled;
      await WakelockPlus.enable();
    } catch (_) {
      if (mounted) setState(() => _wakeFailed = true);
    }
    try {
      if (Platform.isWindows) {
        await windowManager.ensureInitialized();
        _previousFullscreen = await windowManager.isFullScreen();
        await windowManager.setFullScreen(true);
      } else if (Platform.isAndroid || Platform.isIOS) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    } catch (_) {
      /* Reading and app-level full-screen controls remain usable. */
    }
  }

  Future<void> _restoreDeviceMode() async {
    try {
      if (_previousWake != null)
        await WakelockPlus.toggle(enable: _previousWake!);
    } catch (_) {}
    try {
      if (Platform.isWindows && _previousFullscreen != null) {
        await windowManager.setFullScreen(_previousFullscreen!);
      } else if (Platform.isAndroid || Platform.isIOS) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasActive = _active;
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      if (wasActive) _resumeClock = _clock.isRunning;
      _clock.stop();
      _setAuto(false);
      unawaited(_savePosition());
      if (widget.manageDevice)
        unawaited(
          _deviceReady.then((_) async {
            if (mounted && !_active && _previousWake != null) {
              try {
                await WakelockPlus.toggle(enable: _previousWake!);
              } catch (_) {}
            }
          }),
        );
    } else {
      if (_resumeClock) _clock.start();
      if (widget.manageDevice)
        unawaited(
          _deviceReady.then((_) async {
            if (mounted && _active) {
              try {
                await WakelockPlus.enable();
              } catch (_) {}
            }
          }),
        );
    }
  }

  void _tick(Duration elapsed) {
    final previous = _lastFrame;
    _lastFrame = elapsed;
    if (previous == null ||
        !_auto ||
        _overlay ||
        !_active ||
        !_scroll.hasClients)
      return;
    final delta = (elapsed - previous).inMicroseconds / 1000000;
    final next = (_scroll.offset + _speed * delta).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.jumpTo(next);
    if (next >= _scroll.position.maxScrollExtent) _setAuto(false);
  }

  void _updateTicker() {
    _lastFrame = null;
    if (_auto && !_overlay && _active) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  void _setAuto(bool value) {
    if (!mounted) return;
    setState(() => _auto = value);
    _updateTicker();
    if (!value) unawaited(_savePosition());
  }

  Future<void> _savePosition() async {
    try {
      await widget.prefs?.setDouble(_positionKey, _lastOffset);
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      await widget.prefs?.setDouble('SERMON_font', _font);
      await widget.prefs?.setDouble('SERMON_speed', _speed);
      await widget.prefs?.setString('SERMON_theme', _theme);
    } catch (_) {}
  }

  Future<T?> _withOverlay<T>(Future<T?> Function() show) async {
    if (_overlay) return null;
    setState(() => _overlay = true);
    _updateTicker();
    try {
      return await show();
    } finally {
      if (mounted) {
        setState(() => _overlay = false);
        _updateTicker();
      }
    }
  }

  Future<List<Map<String, Object?>>> _loadVerses(SermonVerseLink link) async {
    final reference = link.reference;
    final rows = await widget.db
        .query(
          'verses',
          where: 'book_number = ? AND chapter = ?',
          whereArgs: [reference.bookId, reference.chapter],
          orderBy: 'verse ASC',
        )
        .timeout(const Duration(seconds: 15));
    final selected = rows
        .where((row) => reference.verses.contains(row['verse']))
        .toList();
    if (selected.length != reference.verses.length)
      throw StateError('Ayat tidak tersedia lengkap dalam terjemahan ini.');
    return selected;
  }

  Future<void> _showVerse(SermonVerseLink link) async {
    await _withOverlay<void>(() {
      Future<List<Map<String, Object?>>>? verses;
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _background,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          link.title,
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            color: _link,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tutup ayat',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: Icon(Icons.close, color: _foreground),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: FutureBuilder<List<Map<String, Object?>>>(
                    future: verses ??= _loadVerses(link),
                    builder: (context, snapshot) {
                      if (snapshot.hasError)
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'Ayat belum dapat dimuat. Periksa referensi lalu coba lagi.',
                              style: TextStyle(color: _foreground),
                            ),
                          ),
                        );
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());
                      return ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          for (final row in snapshot.data!)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                '${row['verse']}. ${cleanBibleText(row['text'].toString())}',
                                style: TextStyle(
                                  fontSize: _font,
                                  height: 1.5,
                                  color: _foreground,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Future<void> _showSections() async {
    final section = await _withOverlay<int>(
      () => showModalBottomSheet<int>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Bagian khotbah',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                title: const Text('Awal catatan'),
                onTap: () => Navigator.pop(sheetContext, -1),
              ),
              for (var i = 0; i < _paragraphs.length; i++)
                if (_paragraphs[i].isHeading)
                  ListTile(
                    title: Text(_paragraphs[i].text),
                    onTap: () => Navigator.pop(sheetContext, i),
                  ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || section == null) return;
    _setAuto(false);
    if (section < 0) {
      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      final target = _anchors[section].currentContext;
      if (target != null)
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 300),
          alignment: 0,
        );
    }
    if (mounted) unawaited(_savePosition());
  }

  Future<void> _showSettings() async {
    await _withOverlay<void>(
      () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, changeSheet) {
            void update(VoidCallback change) {
              setState(change);
              changeSheet(() {});
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pengaturan khotbah',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text('Ukuran huruf: ${_font.round()}'),
                    Slider(
                      key: const ValueKey('sermon-font-slider'),
                      value: _font,
                      min: 16,
                      max: 42,
                      divisions: 26,
                      label: '${_font.round()}',
                      onChanged: (value) => update(() => _font = value),
                    ),
                    Text('Kecepatan gulir: ${_speed.round()} piksel/detik'),
                    Slider(
                      key: const ValueKey('sermon-speed-slider'),
                      value: _speed,
                      min: 5,
                      max: 80,
                      divisions: 75,
                      label: '${_speed.round()}',
                      onChanged: (value) => update(() => _speed = value),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final entry in {
                          'light': 'Terang',
                          'sepia': 'Sepia',
                          'dark': 'Gelap',
                        }.entries)
                          ChoiceChip(
                            label: Text(entry.value),
                            selected: _theme == entry.key,
                            onSelected: (_) => update(() => _theme = entry.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Gulir otomatis dijeda saat ayat dibuka. Menggulir dengan tangan menghentikan gulir otomatis.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Selesai'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    if (mounted) unawaited(_saveSettings());
  }

  Future<void> _showClock() async {
    await _withOverlay<void>(
      () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Timer khotbah'),
          content: Text('Durasi $_elapsed'),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  if (_clock.isRunning) {
                    _clock.stop();
                  } else {
                    _clock.start();
                  }
                });
                Navigator.pop(dialogContext);
              },
              child: Text(_clock.isRunning ? 'Jeda timer' : 'Lanjutkan timer'),
            ),
            TextButton(
              onPressed: () {
                setState(() => _clock.reset());
                Navigator.pop(dialogContext);
              },
              child: const Text('Ulangi dari nol'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _clockUpdate?.cancel();
    _clock.stop();
    unawaited(_savePosition());
    if (widget.manageDevice)
      unawaited(_deviceReady.then((_) => _restoreDeviceMode()));
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData(
      brightness: _dark ? Brightness.dark : Brightness.light,
      colorSchemeSeed: Colors.indigo,
    ),
    child: Scaffold(
      backgroundColor: _background,
      resizeToAvoidBottomInset: false,
      appBar: _controls
          ? AppBar(
              backgroundColor: _background,
              foregroundColor: _foreground,
              title: const Text('Mode Khotbah'),
              actions: [
                Tooltip(
                  message: _wakeFailed
                      ? 'Layar tetap menyala belum berhasil diaktifkan'
                      : 'Layar tetap menyala',
                  child: Icon(
                    _wakeFailed
                        ? Icons.screen_lock_portrait
                        : Icons.screen_lock_landscape,
                    size: 18,
                  ),
                ),
                IconButton(
                  tooltip: 'Sembunyikan kontrol',
                  onPressed: () => setState(() => _controls = false),
                  icon: const Icon(Icons.visibility_off_outlined),
                ),
              ],
            )
          : null,
      floatingActionButton: !_controls
          ? FloatingActionButton.small(
              tooltip: 'Tampilkan kontrol',
              onPressed: () => setState(() => _controls = true),
              child: const Icon(Icons.tune),
            )
          : null,
      bottomNavigationBar: _controls
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: _auto
                          ? 'Jeda gulir otomatis'
                          : 'Mulai gulir otomatis',
                      onPressed: () => _setAuto(!_auto),
                      icon: Icon(
                        _auto
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Bagian khotbah',
                      onPressed: _showSections,
                      icon: const Icon(Icons.list_alt),
                    ),
                    IconButton(
                      tooltip: 'Pengaturan khotbah',
                      onPressed: _showSettings,
                      icon: const Icon(Icons.tune),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _showClock,
                        icon: const Icon(Icons.timer_outlined, size: 18),
                        label: FittedBox(
                          child: Text(
                            _elapsed,
                            key: const ValueKey('sermon-elapsed'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification &&
                notification.dragDetails != null &&
                _auto)
              _setAuto(false);
            if (notification is ScrollEndNotification && !_auto)
              unawaited(_savePosition());
            return false;
          },
          child: SingleChildScrollView(
            key: const ValueKey('sermon-scroll'),
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.note.title.isEmpty ? 'Tanpa Judul' : widget.note.title,
                  style: TextStyle(
                    fontSize: _font * 1.4,
                    fontWeight: FontWeight.bold,
                    color: _foreground,
                  ),
                ),
                if (widget.note.preacher.isNotEmpty)
                  Text(
                    widget.note.preacher,
                    style: TextStyle(fontSize: _font * .8, color: _foreground),
                  ),
                SermonParagraphView(
                  paragraph: _referenceParagraph,
                  matcher: _matcher,
                  fontSize: _font * .8,
                  foreground: _link,
                  linkColor: _link,
                  dark: _dark,
                  onVerse: _showVerse,
                ),
                const SizedBox(height: 24),
                for (var i = 0; i < _paragraphs.length; i++)
                  Container(
                    key: _anchors[i],
                    child: SermonParagraphView(
                      paragraph: _paragraphs[i],
                      matcher: _matcher,
                      fontSize: _font,
                      foreground: _foreground,
                      linkColor: _link,
                      dark: _dark,
                      onVerse: _showVerse,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
