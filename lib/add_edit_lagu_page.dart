import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

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

  // ⚠️ MASUKKAN API KEY BOS DI SINI
  final String _geminiApiKey = "AIzaSyAeeii-hh9f3EahItxUm05pZ33-D19pSss";

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

  // ==== JURUS PAMUNGKAS: JALUR TOL HTTP ====
  Future<void> _tanyaGemini() async {
    String judul = _etJudul.text.trim();
    if (judul.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ketik judul lagunya dulu, Bos!")));
      return;
    }

    if (_geminiApiKey.isEmpty || _geminiApiKey == "MASUKKAN_API_KEY_GOOGLE_STUDIO_DI_SINI") {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("API Key belum diisi di dalam kode!")));
      return;
    }

    setState(() => _isAskingGemini = true);
    FocusScope.of(context).unfocus(); // Tutup keyboard biar lega

    try {
      // Kita tembak langsung ke server Google pakai HTTP murni
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$_geminiApiKey');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{
            "parts": [{
              "text": "Kamu adalah asisten database gereja. Berikan lirik lagu rohani kristen berjudul '$judul'. HANYA balas dengan format baku ini tanpa basa-basi:\n[Nama Pencipta/Penyanyi Populer]\n[Isi Lirik Lengkap]"
            }]
          }]
        }),
      ).timeout(const Duration(seconds: 15)); // Tambah batas waktu 15 detik

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String hasil = data['candidates'][0]['content']['parts'][0]['text'] ?? "";
        
        if (hasil.isNotEmpty) {
          List<String> lines = hasil.split('\n');
          if (lines.isNotEmpty) {
            _etPencipta.text = lines.first.replaceAll(RegExp(r'[\[\]]'), '').trim(); 
            lines.removeAt(0); 
            _etLirik.text = lines.join('\n').trim(); 
          }
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✨ Lirik sukses disedot lewat Jalur Tol!")));
        }
      } else {
        final errorData = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal dari server: ${errorData['error']['message']}")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Koneksi Error: Cek internet atau coba lagi bos!")));
    } finally {
      setState(() => _isAskingGemini = false);
    }
  }

  Future<void> _saveLagu() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    Map<String, dynamic> songData = {
      "judul": _etJudul.text.trim(),
      "nomor": _etNomor.text.trim(),
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
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ==== KOLOM JUDUL & TOMBOL GEMINI ====
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildField(_etJudul, "Judul Lagu", true),
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
                _buildField(_etPencipta, "Pencipta / Penyanyi", false),
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
      validator: (v) => (mandatory && v!.isEmpty) ? "$label wajib diisi" : null,
    );
  }
}