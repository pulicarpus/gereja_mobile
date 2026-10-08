import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'secrets.dart';
import 'verse_image_design.dart';

class BuatGambarPage extends StatefulWidget {
  final String ayatTeks, referensi;
  final bool loadOnlineBackgrounds;
  const BuatGambarPage({
    super.key,
    required this.ayatTeks,
    required this.referensi,
    this.loadOnlineBackgrounds = true,
  });
  @override
  State<BuatGambarPage> createState() => _BuatGambarPageState();
}

class _BuatGambarPageState extends State<BuatGambarPage> {
  late final VerseImageHistory _history = VerseImageHistory(
    initialVerseImageDesign(widget.ayatTeks, widget.referensi),
  );
  final _search = TextEditingController();
  final _client = http.Client();
  final _screenshot = ScreenshotController();
  List<String> _images = [];
  bool _loading = false, _busy = false;
  String? _imageError;
  String _tab = 'Teks';
  int _request = 0;
  Map<String, Object> get _d => _history.value;
  @override
  void initState() {
    super.initState();
    if (widget.loadOnlineBackgrounds) _fetch('nature');
  }

  @override
  void dispose() {
    _request++;
    _client.close();
    _search.dispose();
    super.dispose();
  }

  void _set(String key, Object value, {bool remember = true}) =>
      setState(() => _history.change(key, value, rememberChange: remember));
  ImageProvider? get _image {
    final path = _d['image'] as String;
    if (path.isEmpty) return null;
    if (path.startsWith('https://')) return NetworkImage(path);
    return FileImage(File(path));
  }

  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _fetch(String query) async {
    if (query.trim().isEmpty || _busy) return;
    if (pixabayApiKey.isEmpty) {
      setState(
        () => _imageError =
            'Pencarian online belum tersedia. Gunakan foto sendiri atau warna latar.',
      );
      return;
    }
    final request = ++_request;
    setState(() {
      _loading = true;
      _imageError = null;
    });
    try {
      final response = await _client
          .get(
            Uri.https('pixabay.com', '/api/', {
              'key': pixabayApiKey,
              'q': query.trim(),
              'image_type': 'photo',
              'per_page': '20',
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw StateError('Pencarian gagal');
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final hits = decoded['hits'] as List;
      final images = hits
          .map((hit) => hit['largeImageURL'])
          .whereType<String>()
          .where((url) => url.startsWith('https://'))
          .toList();
      if (!mounted || request != _request) return;
      setState(() {
        _images = images;
        _loading = false;
        _imageError = images.isEmpty
            ? 'Tidak ada gambar. Coba kata lain.'
            : null;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _imageError =
            'Gambar online belum dapat dimuat. Foto sendiri dan warna latar tetap tersedia.';
      });
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (!mounted || result == null || _busy) return;
      final path = result.files.single.path;
      if (path == null) throw StateError('Foto tidak dapat dibuka');
      final file = File(path);
      if (await file.length() > 20 * 1024 * 1024) {
        _message('Pilih foto berukuran maksimal 20 MB.');
        return;
      }
      if (!mounted) return;
      Object? imageError;
      await precacheImage(
        FileImage(file),
        context,
        onError: (error, stack) {
          imageError = error;
        },
      );
      if (imageError != null) throw StateError('Foto tidak dapat dibaca');
      if (!mounted || _busy) return;
      _history.remember();
      setState(() {
        _history.change('image', path, rememberChange: false);
        _history.change('background', 'photo', rememberChange: false);
      });
    } catch (_) {
      _message('Foto belum dapat dibuka. Coba foto JPEG atau PNG lain.');
    }
  }

  Future<void> _editText() async {
    final changed = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => VerseTextEditDialog(design: _d),
    );
    if (mounted && changed != null && !_busy) {
      _history.remember();
      setState(() {
        for (final field in changed.entries) {
          _history.change(field.key, field.value, rememberChange: false);
        }
      });
    }
  }

  Future<void> _export({required bool share}) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final provider = _d['background'] == 'photo' ? _image : null;
      if (provider != null) {
        Object? imageError;
        await precacheImage(
          provider,
          context,
          onError: (error, stack) {
            imageError = error;
          },
        ).timeout(const Duration(seconds: 20));
        if (imageError != null)
          throw StateError('Latar foto belum siap. Pilih foto lain.');
      }
      if (!mounted) return;
      final Uint8List bytes = await _screenshot.captureFromWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 360,
            height: 360 / (_d['ratio'] as double),
            child: VerseImageCanvas(
              design: Map.of(_d),
              backgroundImage: provider,
            ),
          ),
        ),
        context: context,
        targetSize: Size(360, 360 / (_d['ratio'] as double)),
        pixelRatio: 3,
        delay: const Duration(milliseconds: 30),
      );
      if (!mounted) return;
      final name = 'ayat_gkii_${DateTime.now().millisecondsSinceEpoch}.png';
      if (!share &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: [
            const XTypeGroup(label: 'Gambar PNG', extensions: ['png']),
          ],
        );
        if (location == null) return;
        await File(location.path).writeAsBytes(bytes, flush: true);
        _message('Gambar berhasil disimpan.');
      } else {
        final folder = await getTemporaryDirectory();
        final file = await File(
          '${folder.path}/$name',
        ).writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        if (share) {
          final box = context.findRenderObject() as RenderBox?;
          await Share.shareXFiles(
            [XFile(file.path)],
            text: 'Renungan hari ini: ${_d['reference']}',
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          );
        } else {
          await Gal.putImage(file.path);
          _message('Gambar berhasil disimpan ke galeri.');
        }
      }
    } catch (_) {
      _message(
        'Gambar belum dapat diekspor. Periksa latar foto, lalu coba lagi.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _slider(String label, String key, double min, double max) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Slider(
        value: (_d[key] as double).clamp(min, max),
        min: min,
        max: max,
        onChangeStart: (_) => _history.remember(),
        onChanged: (value) => _set(key, value, remember: false),
      ),
    ],
  );
  Widget _colors(String label, String key) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children:
            [
                  Colors.white,
                  Colors.black,
                  Colors.orangeAccent,
                  Colors.yellow,
                  Colors.indigo,
                  Colors.blue,
                  Colors.purple,
                  Colors.pink,
                  Colors.teal,
                  Colors.green,
                  Colors.brown,
                  const Color(0xff172554),
                ]
                .map(
                  (color) => Semantics(
                    label: '$label ${color.value.toRadixString(16)}',
                    selected: _d[key] == color,
                    child: InkWell(
                      onTap: () => _set(key, color),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _d[key] == color
                                ? Colors.orange
                                : Colors.grey,
                            width: _d[key] == color ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
      ),
      const SizedBox(height: 16),
    ],
  );
  Widget _choices<T extends Object>(
    String label,
    String key,
    Map<String, T> values,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Wrap(
        spacing: 6,
        children: values.entries
            .map(
              (entry) => ChoiceChip(
                label: Text(entry.key),
                selected: _d[key] == entry.value,
                onSelected: (_) => _set(key, entry.value),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 12),
    ],
  );
  Widget _switch(String label, String key) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: _d[key] as bool,
    onChanged: (value) => _set(key, value),
  );
  Widget _tools() => Column(
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: ['Teks', 'Latar', 'Tata letak']
              .map(
                (tab) => Padding(
                  padding: const EdgeInsets.all(4),
                  child: ChoiceChip(
                    label: Text(tab),
                    selected: _tab == tab,
                    onSelected: (_) => setState(() => _tab = tab),
                  ),
                ),
              )
              .toList(),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: _tab == 'Teks'
              ? [
                  OutlinedButton.icon(
                    onPressed: _editText,
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit ayat & teks tambahan'),
                  ),
                  _choices('Jenis font', 'font', {
                    'Standar': 'Standar',
                    'Serif': 'Serif',
                    'Monospace': 'Monospace',
                  }),
                  _slider('Ukuran teks', 'fontSize', 14, 42),
                  _slider('Jarak baris', 'lineHeight', 1, 2),
                  _switch('Tebal', 'bold'),
                  _switch('Miring', 'italic'),
                  _switch('Bayangan teks', 'shadow'),
                  _choices('Perataan teks', 'align', {
                    'Kiri': TextAlign.left,
                    'Tengah': TextAlign.center,
                    'Kanan': TextAlign.right,
                  }),
                  _colors('Warna teks', 'textColor'),
                  _colors('Warna referensi', 'referenceColor'),
                ]
              : _tab == 'Latar'
              ? [
                  _choices('Jenis latar', 'background', {
                    'Gradasi': 'gradient',
                    'Warna polos': 'solid',
                    'Foto': 'photo',
                  }),
                  _colors('Warna latar', 'backgroundColor'),
                  if (_d['background'] == 'gradient')
                    _colors('Warna gradasi kedua', 'secondColor'),
                  OutlinedButton.icon(
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Pilih foto dari perangkat'),
                  ),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: 'Cari gambar online',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => _fetch(_search.text),
                      ),
                    ),
                    onSubmitted: _fetch,
                  ),
                  Wrap(
                    spacing: 6,
                    children:
                        {
                              'Alam': 'nature',
                              'Senja': 'sunset',
                              'Gunung': 'mountain',
                              'Salib': 'cross',
                              'Bintang': 'starry sky',
                            }.entries
                            .map(
                              (theme) => ActionChip(
                                label: Text(theme.key),
                                onPressed: () => _fetch(theme.value),
                              ),
                            )
                            .toList(),
                  ),
                  if (_loading) const LinearProgressIndicator(),
                  if (_imageError != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(_imageError!),
                    ),
                  if (_images.isNotEmpty)
                    SizedBox(
                      height: 90,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: _images.map((url) {
                          return Padding(
                            padding: const EdgeInsets.all(4),
                            child: InkWell(
                              onTap: () {
                                _history.remember();
                                setState(() {
                                  _history.change(
                                    'image',
                                    url,
                                    rememberChange: false,
                                  );
                                  _history.change(
                                    'background',
                                    'photo',
                                    rememberChange: false,
                                  );
                                });
                              },
                              child: Image.network(
                                url,
                                width: 70,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (_, error, stack) =>
                                    const SizedBox(
                                      width: 70,
                                      child: Icon(Icons.broken_image),
                                    ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  _slider('Gelapkan latar', 'overlay', 0, .8),
                  if (_d['background'] == 'photo') ...[
                    _slider('Zoom foto', 'zoom', 1, 3),
                    _slider('Geser foto horizontal', 'imageX', -1, 1),
                    _slider('Geser foto vertikal', 'imageY', -1, 1),
                  ],
                ]
              : [
                  _choices('Ukuran gambar', 'ratio', {
                    'Story 9:16': 9 / 16,
                    'Kotak 1:1': 1.0,
                    'Feed 4:5': 4 / 5,
                    'Lanskap 16:9': 16 / 9,
                  }),
                  _slider('Posisi teks horizontal', 'textX', -1, 1),
                  _slider('Posisi teks vertikal', 'textY', -1, 1),
                  _slider('Lebar area teks', 'textWidth', .45, 1),
                  const Text('Teks juga bisa digeser langsung pada pratinjau.'),
                  _switch('Tampilkan GKII Mobile', 'watermark'),
                  OutlinedButton.icon(
                    onPressed: () => setState(
                      () => _history.replace(
                        initialVerseImageDesign(
                          widget.ayatTeks,
                          widget.referensi,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Kembalikan desain awal'),
                  ),
                ],
        ),
      ),
    ],
  );
  Widget _preview() => LayoutBuilder(
    builder: (context, constraints) => Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: GestureDetector(
            onPanStart: (_) => _history.remember(),
            onPanUpdate: (details) {
              final width = 360.0;
              final height = 360 / (_d['ratio'] as double);
              setState(() {
                _history.change(
                  'textX',
                  ((_d['textX'] as double) + 2 * details.delta.dx / width)
                      .clamp(-1.0, 1.0),
                  rememberChange: false,
                );
                _history.change(
                  'textY',
                  ((_d['textY'] as double) + 2 * details.delta.dy / height)
                      .clamp(-1.0, 1.0),
                  rememberChange: false,
                );
              });
            },
            child: SizedBox(
              width: 360,
              height: 360 / (_d['ratio'] as double),
              child: VerseImageCanvas(design: _d, backgroundImage: _image),
            ),
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.grey.shade200,
    appBar: AppBar(
      title: const Text('Edit gambar ayat'),
      actions: [
        IconButton(
          tooltip: 'Urungkan',
          onPressed: !_busy && _history.canUndo
              ? () => setState(_history.undo)
              : null,
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: 'Ulangi',
          onPressed: !_busy && _history.canRedo
              ? () => setState(_history.redo)
              : null,
          icon: const Icon(Icons.redo),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: IgnorePointer(
              ignoring: _busy,
              child: LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 850
                    ? Row(
                        children: [
                          Expanded(child: _preview()),
                          SizedBox(
                            width: 350,
                            child: ColoredBox(
                              color: Colors.white,
                              child: _tools(),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: _preview()),
                          SizedBox(
                            height: (constraints.maxHeight * .45).clamp(
                              0.0,
                              300.0,
                            ),
                            child: ColoredBox(
                              color: Colors.white,
                              child: _tools(),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _export(share: false),
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Simpan PNG'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _export(share: true),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.share),
                    label: const Text('Bagikan'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class VerseTextEditDialog extends StatefulWidget {
  final Map<String, Object> design;
  const VerseTextEditDialog({super.key, required this.design});
  @override
  State<VerseTextEditDialog> createState() => _VerseTextEditDialogState();
}

class _VerseTextEditDialogState extends State<VerseTextEditDialog> {
  late final verse = TextEditingController(
    text: widget.design['verse'] as String,
  );
  late final reference = TextEditingController(
    text: widget.design['reference'] as String,
  );
  late final caption = TextEditingController(
    text: widget.design['caption'] as String,
  );
  @override
  void dispose() {
    verse.dispose();
    reference.dispose();
    caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit teks gambar'),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: verse,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Teks ayat'),
            ),
            TextField(
              controller: reference,
              decoration: const InputDecoration(labelText: 'Referensi'),
            ),
            TextField(
              controller: caption,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Teks tambahan (opsional)',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () {
          if (verse.text.trim().isNotEmpty)
            Navigator.pop(context, {
              'verse': verse.text.trim(),
              'reference': reference.text.trim(),
              'caption': caption.text.trim(),
            });
        },
        child: const Text('Terapkan'),
      ),
    ],
  );
}
