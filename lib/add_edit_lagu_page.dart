import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'secrets.dart';
import 'loading_sultan.dart';
import 'user_manager.dart';

class AddEditLaguPage extends StatefulWidget {
  final String? songId;
  final String? defaultCategory;

  const AddEditLaguPage({
    super.key,
    this.songId,
    this.defaultCategory,
  });

  @override
  State<AddEditLaguPage> createState() => _AddEditLaguPageState();
}

class _AddEditLaguPageState extends State<AddEditLaguPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final _etJudul = TextEditingController();
  final _etNomor = TextEditingController();
  final _etPencipta = TextEditingController();
  final _etLirik = TextEditingController();

  String _selectedKategori = "NKI";
  bool _isLoading = false;
  bool _isAskingGemini = false;
  String? _loadError;

  final String _geminiApiKey = geminiApiKey;

  bool get _canManageSongs => UserManager().isAdmin();

  @override
  void initState() {
    super.initState();
    _selectedKategori = _normalizeCategory(widget.defaultCategory);
    if (widget.songId != null) {
      _loadDataLagu();
    }
  }

  @override
  void dispose() {
    _etJudul.dispose();
    _etNomor.dispose();
    _etPencipta.dispose();
    _etLirik.dispose();
    super.dispose();
  }

  String _normalizeCategory(dynamic raw) {
    final value = raw?.toString().trim().toUpperCase() ?? "";
    return value == "KONTEMPORER" ? "KONTEMPORER" : "NKI";
  }

  String _normalizeTitle(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _text(dynamic raw) => raw?.toString().trim() ?? "";

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _loadDataLagu() async {
    if (!_canManageSongs) return;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final doc = await _db.collection("songs").doc(widget.songId).get();
      if (!mounted) return;

      if (!doc.exists) {
        setState(() {
          _loadError = "Lagu tidak ditemukan.";
          _isLoading = false;
        });
        return;
      }

      final data = doc.data()!;
      setState(() {
        _etJudul.text = _text(data['judul']);
        _etNomor.text = _text(data['nomor']);
        _etPencipta.text = _text(data['pencipta']);
        _etLirik.text = _text(data['lirik']);
        _selectedKategori = _normalizeCategory(data['kategori']);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Gagal memuat lagu: $e");
      if (mounted) {
        setState(() {
          _loadError = "Gagal memuat data lagu.";
          _isLoading = false;
        });
      }
    }
  }

  String? _extractGeminiText(dynamic decoded) {
    if (decoded is! Map) return null;
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) return null;

    final candidate = candidates.first;
    if (candidate is! Map) return null;

    final content = candidate['content'];
    if (content is! Map) return null;

    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) return null;

    for (final part in parts) {
      if (part is Map && part['text'] != null) {
        final text = part['text'].toString().trim();
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  Future<void> _tanyaGemini() async {
    if (!_canManageSongs || _isAskingGemini || _isLoading) return;

    final kataKunci = _etJudul.text.trim();
    final penyanyiTarget = _etPencipta.text.trim();

    if (kataKunci.isEmpty) {
      _showSnack("Ketik judul atau potongan lirik terlebih dahulu.");
      return;
    }
    if (_geminiApiKey.isEmpty) {
      _showSnack(
        "Layanan pencarian lirik belum dikonfigurasi.",
        color: Colors.orange,
      );
      return;
    }

    setState(() => _isAskingGemini = true);
    FocusScope.of(context).unfocus();

    var instruksi =
        "Carikan lirik lagu rohani Kristen lengkap berdasarkan kata kunci: '$kataKunci'. ";
    if (penyanyiTarget.isNotEmpty) {
      instruksi +=
          "Utamakan versi dari penyanyi atau grup: '$penyanyiTarget'. ";
    }
    instruksi +=
        "Gunakan Google Search bila diperlukan. Berikan hasil yang paling cocok. "
        "Admin akan meninjau hasil sebelum menyimpan.";

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_geminiApiKey',
      );

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              "contents": [
                {
                  "parts": [
                    {
                      "text":
                          "Kamu adalah asisten database lagu gereja. $instruksi\n"
                          "Balas dengan format tepat:\n"
                          "[Judul Lagu]\n"
                          "[Nama Penyanyi/Grup]\n"
                          "[Isi Lirik Lengkap]"
                    }
                  ]
                }
              ],
              "tools": [
                {"googleSearch": {}}
              ]
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _showSnack(
          "Pencarian lirik sedang gagal (kode ${response.statusCode}).",
          color: Colors.orange,
        );
        return;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        _showSnack(
          "Respons layanan lirik tidak dapat dibaca.",
          color: Colors.orange,
        );
        return;
      }

      var hasil = _extractGeminiText(decoded);
      if (hasil == null || hasil.trim().isEmpty) {
        _showSnack(
          "Layanan tidak mengembalikan lirik. Coba kata kunci lain.",
          color: Colors.orange,
        );
        return;
      }

      hasil = hasil.replaceAll('**', '').trim();
      final lines = hasil
          .split('\n')
          .map((e) => e.trimRight())
          .where((e) => e.trim().isNotEmpty)
          .toList();

      if (lines.length < 3) {
        _showSnack(
          "Format hasil pencarian tidak lengkap. Coba lagi.",
          color: Colors.orange,
        );
        return;
      }

      final title = lines[0]
          .replaceAll(RegExp(r'^[\[\s]+|[\]\s]+$'), '')
          .trim();
      final artist = lines[1]
          .replaceAll(RegExp(r'^[\[\s]+|[\]\s]+$'), '')
          .trim();
      final lyrics = lines.sublist(2).join('\n').trim();

      if (title.isEmpty || lyrics.length < 20) {
        _showSnack(
          "Hasil lirik terlalu pendek atau tidak valid.",
          color: Colors.orange,
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _etJudul.text = title;
        _etPencipta.text = artist;
        _etLirik.text = lyrics;
      });
      _showSnack(
        "Hasil lirik dimasukkan ke form. Periksa sebelum menyimpan.",
        color: Colors.green,
      );
    } catch (e) {
      debugPrint("Gemini lagu gagal: $e");
      _showSnack(
        "Pencarian lirik gagal. Periksa koneksi dan coba lagi.",
        color: Colors.orange,
      );
    } finally {
      if (mounted) setState(() => _isAskingGemini = false);
    }
  }

  Future<String?> _findDuplicateMessage({
    required String title,
    required String number,
    required String category,
  }) async {
    final snapshot = await _db.collection("songs").get();
    final normalizedTitle = _normalizeTitle(title);

    for (final doc in snapshot.docs) {
      if (doc.id == widget.songId) continue;

      final data = doc.data();
      final existingTitle = _normalizeTitle(_text(data['judul']));
      if (existingTitle.isNotEmpty && existingTitle == normalizedTitle) {
        return "Lagu dengan judul '$title' sudah ada.";
      }

      // Nomor NKI dibandingkan apa adanya. Tidak ada normalisasi 1/01/001.
      if (category == "NKI" && number.isNotEmpty) {
        final existingCategory = _normalizeCategory(data['kategori']);
        final existingNumber = _text(data['nomor']);
        if (existingCategory == "NKI" && existingNumber == number) {
          return "Buku NKI nomor '$number' sudah ada.";
        }
      }
    }
    return null;
  }

  void _showDuplicateAlert(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 30),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "Duplikat Data",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          "$message\n\nPeriksa daftar Buku Nyanyian sebelum menambahkan data baru.",
          style: const TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Mengerti"),
          ),
        ],
      ),
    );
  }

  Future<void> _saveLagu() async {
    if (!_canManageSongs) {
      _showSnack(
        "Anda tidak memiliki izin untuk mengubah Buku Nyanyian.",
        color: Colors.red,
      );
      return;
    }
    if (_isLoading || !(_formKey.currentState?.validate() ?? false)) return;

    final judulBaru = _etJudul.text.trim();
    final nomorBaru = _etNomor.text.trim();
    final pencipta = _etPencipta.text.trim();
    final lirik = _etLirik.text.trim();

    setState(() => _isLoading = true);

    try {
      final duplicate = await _findDuplicateMessage(
        title: judulBaru,
        number: nomorBaru,
        category: _selectedKategori,
      );
      if (duplicate != null) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showDuplicateAlert(duplicate);
        }
        return;
      }
    } catch (e) {
      debugPrint("Gagal memeriksa duplikat lagu: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack(
          "Tidak dapat memeriksa duplikat. Penyimpanan dibatalkan agar database tetap aman.",
          color: Colors.orange,
        );
      }
      return;
    }

    final songData = <String, dynamic>{
      "judul": judulBaru,
      "nomor": nomorBaru,
      "pencipta": pencipta,
      "lirik": lirik,
      "kategori": _selectedKategori,
      "lastUpdate": FieldValue.serverTimestamp(),
    };

    try {
      if (widget.songId != null) {
        await _db.collection("songs").doc(widget.songId).update(songData);
      } else {
        await _db.collection("songs").add(songData);
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint("Gagal menyimpan lagu: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack("Gagal menyimpan lagu.", color: Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canManageSongs) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Buku Nyanyian"),
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "Anda tidak memiliki izin untuk menambah atau mengedit lagu.",
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.songId == null ? "Tambah Lagu" : "Edit Lagu"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          if (!_isLoading)
            IconButton(
              onPressed: _saveLagu,
              icon: const Icon(Icons.check, size: 28),
            )
        ],
      ),
      body: _isLoading
          ? LoadingSultan(size: 80)
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 52,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(height: 12),
                        Text(_loadError!),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _loadDataLagu,
                          child: const Text("COBA LAGI"),
                        ),
                      ],
                    ),
                  ),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _buildField(
                              _etJudul,
                              "Judul Lagu atau Potongan Lirik",
                              true,
                              maxLength: 180,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 1,
                            child: SizedBox(
                              height: 55,
                              child: ElevatedButton.icon(
                                onPressed:
                                    _isAskingGemini ? null : _tanyaGemini,
                                icon: _isAskingGemini
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.auto_awesome,
                                        color: Colors.amber,
                                      ),
                                label: Text(
                                  _isAskingGemini
                                      ? "Loading"
                                      : "Tanya\nGemini",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.1,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple[700],
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: _buildField(
                              _etNomor,
                              "Nomor (Opsional)",
                              false,
                              maxLength: 20,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedKategori,
                              decoration: InputDecoration(
                                labelText: "Kategori",
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              items: const ["NKI", "KONTEMPORER"]
                                  .map(
                                    (k) => DropdownMenuItem(
                                      value: k,
                                      child: Text(k),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _selectedKategori = v);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      _buildField(
                        _etPencipta,
                        "Pencipta / Penyanyi",
                        false,
                        maxLength: 180,
                      ),
                      const SizedBox(height: 15),
                      _buildField(
                        _etLirik,
                        "Isi Lirik",
                        true,
                        maxLines: 18,
                        maxLength: 20000,
                        sentences: true,
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton(
                        onPressed: _saveLagu,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 55),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "SIMPAN KE DATABASE",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    bool mandatory, {
    int maxLines = 1,
    int? maxLength,
    bool sentences = false,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      textCapitalization:
          sentences ? TextCapitalization.sentences : TextCapitalization.words,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        alignLabelWithHint: maxLines > 1,
      ),
      validator: (v) {
        if (mandatory && (v ?? '').trim().isEmpty) {
          return "Kolom ini wajib diisi";
        }
        return null;
      },
    );
  }
}
