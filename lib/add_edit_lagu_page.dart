import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

// 👇 IMPORT BRANKAS RAHASIA KITA 👇
import 'secrets.dart';

class AddEditLaguPage extends StatefulWidget {
  final String? songId;
  final String? defaultCategory;

  const AddEditLaguPage({super.key, this.songId, this.defaultCategory});

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

  // 👇 AMBIL KUNCI DARI BRANKAS RAHASIA 👇
  final String _geminiApiKey = geminiApiKey;

  @override
  void initState() {
    super.initState();
    _selectedKategori = widget.defaultCategory ?? "NKI";
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

  Future<void> _loadDataLagu() async {
    setState(() => _isLoading = true);
    var doc = await _db.collection("songs").doc(widget.songId).get();
    if (doc.exists) {
      var data = doc.data()!;
      _etJudul.text = data['judul'] ?? "";
      _etNomor.text = data['nomor'] ?? "";
      _etPencipta.text = data['pencipta'] ?? "";
      _etLirik.text = data['lirik'] ?? "";
      _selectedKategori = data['kategori'] ?? "NKI";
    }
    setState(() => _isLoading = false);
  }

  // ==== JURUS SULTAN: PENCARIAN DENGAN GOOGLE SEARCH GROUNDING ====
  Future<void> _tanyaGemini() async {
    String kataKunci = _etJudul.text.trim();
    String penyanyiTarget = _etPencipta.text.trim();

    if (kataKunci.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ketik judul atau potongan liriknya dulu, Bos!")));
      return;
    }

    if (_geminiApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("API Key di brankas kosong!")));
      return;
    }

    setState(() => _isAskingGemini = true);
    FocusScope.of(context).unfocus();

    String instruksi = "Carikan lirik lagu rohani kristen lengkap berdasarkan kata kunci: '$kataKunci'. ";
    if (penyanyiTarget.isNotEmpty) {
      instruksi += "Utamakan versi dari penyanyi: '$penyanyiTarget'. ";
    }
    instruksi += "CARI DI GOOGLE SEARCH jika data tidak tersedia di memori kamu. Berikan lirik yang paling akurat sesuai hasil pencarian. ";

    try {
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_geminiApiKey');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{
            "parts": [{
              "text": "Kamu adalah asisten database gereja. $instruksi HANYA balas dengan format baku 3 baris ini (DILARANG MINTA MAAF): \n[Judul Lagu]\n[Nama Penyanyi/Grup]\n[Isi Lirik Lengkap]"
            }]
          }],
          "tools": [
            {
              "googleSearch": {} 
            }
          ]
        }),
      ).timeout(const Duration(seconds: 20)); 

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        String hasil = data['candidates'][0]['content']['parts'][0]['text'] ?? "";
        
        if (hasil.isNotEmpty) {
          hasil = hasil.replaceAll('**', '').trim();
          List<String> lines = hasil.split('\n');
          lines.removeWhere((element) => element.trim().isEmpty);

          if (lines.length >= 3) {
            if (lines[0].toLowerCase().contains("maaf") || lines[0].toLowerCase().contains("tidak dapat")) {
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lagu benar-benar tidak ada di internet bos!")));
            } else {
              _etJudul.text = lines[0].replaceAll(RegExp(r'[\[\]]'), '').trim();
              _etPencipta.text = lines[1].replaceAll(RegExp(r'[\[\]]'), '').trim();
              lines.removeRange(0, 2);
              _etLirik.text = lines.join('\n').trim();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✨ Lirik akurat mendarat via Google Search!")));
            }
          } else {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Format balasan berantakan, coba lagi bos!")));
          }
        }
      } else {
        final errorData = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: ${errorData['error']['message']}")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Koneksi lemot atau API Error, coba lagi bos!")));
    } finally {
      setState(() => _isAskingGemini = false);
    }
  }

  // 👇 FUNGSI BANTUAN UNTUK MENAMPILKAN ALERT DUPLIKAT 👇
  void _showDuplicateAlert(String pesan) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 30),
            SizedBox(width: 10),
            Text("Duplikat Data", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          ],
        ),
        content: Text(
          "$pesan\n\nSilakan cari langsung di daftar buku nyanyian, tidak perlu ditambahkan lagi agar database tetap bersih dan tidak bentrok antar gereja.",
          style: const TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context),
            child: const Text("Mengerti"),
          ),
        ],
      ),
    );
  }

  Future<void> _saveLagu() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    String judulBaru = _etJudul.text.trim();
    String nomorBaru = _etNomor.text.trim();

    // =======================================================================
    // 👇 SATPAM ANTI-DUPLIKAT (HANYA BERLAKU SAAT TAMBAH LAGU BARU) 👇
    // =======================================================================
    if (widget.songId == null) {
      try {
        // 1. Cek Apakah Judul Sudah Ada
        var cekJudul = await _db.collection("songs").where("judul", isEqualTo: judulBaru).limit(1).get();
        if (cekJudul.docs.isNotEmpty) {
          setState(() => _isLoading = false);
          _showDuplicateAlert("Lagu dengan judul '$judulBaru' sudah pernah ditambahkan.");
          return; // ⛔ STOP PROSES SIMPAN!
        }

        // 2. Cek Apakah Nomor NKI Sudah Ada (Jika Kategori = NKI)
        if (nomorBaru.isNotEmpty && _selectedKategori == "NKI") {
          var cekNomor = await _db.collection("songs")
              .where("nomor", isEqualTo: nomorBaru)
              .where("kategori", isEqualTo: "NKI")
              .limit(1).get();
          if (cekNomor.docs.isNotEmpty) {
            setState(() => _isLoading = false);
            _showDuplicateAlert("Buku NKI nomor '$nomorBaru' sudah pernah ditambahkan.");
            return; // ⛔ STOP PROSES SIMPAN!
          }
        }
      } catch (e) {
        // Jika cek gagal karena koneksi, abaikan & lanjut simpan agar fungsi tetap berjalan
        debugPrint("Gagal cek duplikat: $e");
      }
    }
    // =======================================================================
    // 👆 SATPAM SELESAI BERTUGAS 👆
    // =======================================================================

    Map<String, dynamic> songData = {
      "judul": judulBaru,
      "nomor": nomorBaru,
      "pencipta": _etPencipta.text.trim(),
      "lirik": _etLirik.text.trim(),
      "kategori": _selectedKategori,
      "lastUpdate": FieldValue.serverTimestamp(),
    };

    try {
      if (widget.songId != null) {
        await _db.collection("songs").doc(widget.songId).update(songData);
      } else {
        await _db.collection("songs").add(songData);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error menyimpan: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.songId == null ? "Tambah Lagu" : "Edit Lagu"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          if (!_isLoading) IconButton(onPressed: _saveLagu, icon: const Icon(Icons.check, size: 28))
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
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
                      child: _buildField(_etJudul, "Judul Lagu atau Potongan Lirik", true),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: SizedBox(
                        height: 55, 
                        child: ElevatedButton.icon(
                          onPressed: _isAskingGemini ? null : _tanyaGemini,
                          icon: _isAskingGemini 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.auto_awesome, color: Colors.amber),
                          label: Text(_isAskingGemini ? "Loading" : "Tanya\nGemini", style: const TextStyle(fontSize: 12, height: 1.1)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple[700], 
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 5)
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                Row(
                  children: [
                    Expanded(child: _buildField(_etNomor, "Nomor (Opsional)", false)),
                    const SizedBox(width: 15),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedKategori,
                        decoration: InputDecoration(
                          labelText: "Kategori", 
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))
                        ),
                        items: ["NKI", "KONTEMPORER"].map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                        onChanged: (v) => setState(() => _selectedKategori = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                _buildField(_etPencipta, "Pencipta / Penyanyi (Isi untuk filter spesifik)", false),
                const SizedBox(height: 15),
                _buildField(_etLirik, "Isi Lirik", true, maxLines: 18),
                const SizedBox(height: 30),
                
                ElevatedButton(
                  onPressed: _saveLagu,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  child: const Text("SIMPAN KE DATABASE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, bool mandatory, {int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: label, 
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        alignLabelWithHint: maxLines > 1, 
      ),
      validator: (v) => (mandatory && v!.isEmpty) ? "Kolom ini wajib diisi" : null,
    );
  }
}