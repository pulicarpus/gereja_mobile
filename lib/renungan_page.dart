import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

class RenunganPage extends StatefulWidget {
  const RenunganPage({super.key});

  @override
  State<RenunganPage> createState() => _RenunganPageState();
}

class _RenunganPageState extends State<RenunganPage> {
  static const _sourceUrl = "https://alkitab.mobi/renungan/rh/";
  static const _keyTitle = "judul_hari_ini";
  static const _keyBody = "isi_hari_ini";
  static const _keyDate = "tanggal_renungan_cache";
  static const _keyFontSize = "renungan_font_size";

  SharedPreferences? _prefs;

  String _judul = "Renungan Harian";
  String _isi = "Sedang mengambil data terbaru...";
  String? _cacheDateKey;
  bool _isLoading = false;
  bool _isFromCache = false;
  String? _loadError;
  int _loadGeneration = 0;

  double _fontSize = 18.0;
  double _baseFontSize = 18.0;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  String _dateKey(DateTime date) =>
      "${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

  String _formatTanggalIndonesia(DateTime date) {
    const hari = [
      'Minggu',
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu'
    ];
    const bulan = [
      '',
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember'
    ];
    final indexHari = date.weekday == 7 ? 0 : date.weekday;
    return "${hari[indexHari]}, ${date.day} ${bulan[date.month]} ${date.year}";
  }

  DateTime? _parseDateKey(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    _prefs = prefs;
    final cachedTitle = prefs.getString(_keyTitle)?.trim();
    final cachedBody = prefs.getString(_keyBody)?.trim();
    final cachedDate = prefs.getString(_keyDate);
    final savedFont = prefs.getDouble(_keyFontSize);

    setState(() {
      if (cachedTitle != null && cachedTitle.isNotEmpty) {
        _judul = cachedTitle;
      }
      if (cachedBody != null && cachedBody.isNotEmpty) {
        _isi = cachedBody;
        _isFromCache = true;
      }
      _cacheDateKey = cachedDate;
      if (savedFont != null) {
        _fontSize = savedFont.clamp(14.0, 36.0).toDouble();
        _baseFontSize = _fontSize;
      }
    });

    await _ambilDataRenungan(showFailureSnack: cachedBody == null);
  }

  Future<void> _saveFontSize() async {
    final prefs = _prefs;
    if (prefs != null) {
      await prefs.setDouble(_keyFontSize, _fontSize);
    }
  }

  void _zoomIn() {
    setState(() {
      _fontSize = (_fontSize + 2).clamp(14.0, 36.0).toDouble();
      _baseFontSize = _fontSize;
    });
    _saveFontSize();
  }

  void _zoomOut() {
    setState(() {
      _fontSize = (_fontSize - 2).clamp(14.0, 36.0).toDouble();
      _baseFontSize = _fontSize;
    });
    _saveFontSize();
  }

  Future<void> _ambilDataRenungan({bool showFailureSnack = true}) async {
    if (_isLoading) return;

    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final response = await http
          .get(Uri.parse(_sourceUrl))
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw Exception("HTTP ${response.statusCode}");
      }

      final dom.Document doc = html_parser.parse(response.body);

      String bacaan = "";
      for (final a in doc.querySelectorAll("a")) {
        if (a.attributes['href']?.contains("/tb/") == true) {
          final candidate = a.text.trim();
          if (candidate.isNotEmpty) {
            bacaan = candidate;
            break;
          }
        }
      }

      String judulFix = "Renungan Harian";
      for (final b in doc.querySelectorAll("b")) {
        final t = b.text.trim();
        if (t.length > 5 &&
            !t.toLowerCase().contains("renungan harian") &&
            !t.toLowerCase().contains("mobile") &&
            !t.toLowerCase().contains("nas:") &&
            !t.toLowerCase().contains("bacaan")) {
          judulFix = t;
          break;
        }
      }

      final listIsi = <String>[];
      const blacklist = [
        "<<",
        ">>",
        "BCA",
        "Diskusi renungan",
        "facebook.com",
        "Ayat Alkitab:"
      ];

      for (final p in doc.querySelectorAll("p")) {
        final teks = p.text.trim();
        final dirty = blacklist.any(
          (word) => teks.toLowerCase().contains(word.toLowerCase()),
        );
        if (teks.length > 15 &&
            !dirty &&
            teks.toLowerCase() != judulFix.toLowerCase() &&
            !teks.toLowerCase().startsWith("bacaan:")) {
          listIsi.add(teks);
        }
      }

      final isiArtikel = listIsi.join("\n\n").trim();
      if (isiArtikel.length < 180 || listIsi.length < 2) {
        throw const FormatException("Struktur renungan tidak dikenali");
      }

      final isiLengkap = bacaan.isEmpty
          ? isiArtikel
          : "Bacaan: $bacaan\n\n$isiArtikel";
      final todayKey = _dateKey(DateTime.now());

      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setString(_keyTitle, judulFix);
      await prefs.setString(_keyBody, isiLengkap);
      await prefs.setString(_keyDate, todayKey);

      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _judul = judulFix;
        _isi = isiLengkap;
        _cacheDateKey = todayKey;
        _isFromCache = false;
        _loadError = null;
      });
    } catch (e) {
      debugPrint("Gagal sinkron renungan: $e");
      if (!mounted || generation != _loadGeneration) return;

      final hasUsableCache = _isi.trim().length >= 80;
      setState(() {
        _isFromCache = hasUsableCache;
        _loadError = hasUsableCache
            ? "Tidak dapat memperbarui. Menampilkan renungan tersimpan."
            : "Renungan belum dapat dimuat.";
        if (!hasUsableCache) {
          _judul = "Renungan Harian";
          _isi = "Tarik layar ke bawah untuk mencoba lagi.";
        }
      });

      if (showFailureSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasUsableCache
                  ? "Gagal sinkron. Renungan tersimpan tetap ditampilkan."
                  : "Gagal memuat renungan. Periksa koneksi internet.",
            ),
          ),
        );
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _hasShareableContent => _isi.trim().length >= 80;

  void _shareRenungan() {
    if (!_hasShareableContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Renungan belum siap dibagikan.")),
      );
      return;
    }

    final contentDate = _parseDateKey(_cacheDateKey) ?? DateTime.now();
    final tanggal = _formatTanggalIndonesia(contentDate);
    final status = _isFromCache ? "\n_(tersimpan offline)_" : "";
    final teksShare =
        "*$_judul*\n$tanggal$status\n\n$_isi\n\n_Sumber: alkitab.mobi/renungan/rh/_";
    Share.share(teksShare, subject: "Renungan: $_judul");
  }

  @override
  Widget build(BuildContext context) {
    const mainBgColor = Color(0xFFEFE6D6);
    const paperColor = Color(0xFFFCFBF4);
    const headerIndigo = Color(0xFF1A237E);

    final cachedDate = _parseDateKey(_cacheDateKey);
    final todayKey = _dateKey(DateTime.now());
    final cacheIsOld =
        _cacheDateKey != null && _cacheDateKey!.isNotEmpty && _cacheDateKey != todayKey;
    final shownDate = cachedDate ?? DateTime.now();

    return Scaffold(
      backgroundColor: mainBgColor,
      appBar: AppBar(
        title: const Text("Renungan Harian"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            tooltip: "Perkecil teks",
            onPressed: _zoomOut,
            icon: const Icon(Icons.text_decrease),
          ),
          IconButton(
            tooltip: "Perbesar teks",
            onPressed: _zoomIn,
            icon: const Icon(Icons.text_increase),
          ),
          IconButton(
            tooltip: "Bagikan",
            icon: const Icon(Icons.share),
            onPressed: _hasShareableContent ? _shareRenungan : null,
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () => _ambilDataRenungan(showFailureSnack: true),
            color: Colors.indigo,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatTanggalIndonesia(shownDate),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _isFromCache
                                ? Colors.orange.shade50
                                : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _isFromCache ? "TERSIMPAN" : "TERBARU",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _isFromCache
                                  ? Colors.orange.shade800
                                  : Colors.green.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (cacheIsOld || _loadError != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Text(
                        cacheIsOld
                            ? "Ini renungan tersimpan tanggal ${_formatTanggalIndonesia(shownDate)}. Tarik ke bawah untuk memperbarui."
                            : _loadError!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: paperColor,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _judul,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: headerIndigo,
                          ),
                        ),
                        const Divider(height: 35, thickness: 1.2),
                        GestureDetector(
                          onScaleStart: (_) {
                            _baseFontSize = _fontSize;
                          },
                          onScaleUpdate: (details) {
                            setState(() {
                              _fontSize = (_baseFontSize * details.scale)
                                  .clamp(14.0, 36.0)
                                  .toDouble();
                            });
                          },
                          onScaleEnd: (_) => _saveFontSize(),
                          child: Container(
                            color: Colors.transparent,
                            width: double.infinity,
                            child: Text(
                              _isi,
                              style: TextStyle(
                                fontSize: _fontSize,
                                height: 1.65,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      "Sumber: alkitab.mobi/renungan/rh/",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
          if (_isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                backgroundColor: paperColor,
                color: Colors.indigo,
              ),
            ),
        ],
      ),
    );
  }
}
