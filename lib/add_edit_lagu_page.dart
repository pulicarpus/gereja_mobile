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

  // ⚠️ MASUKKAN API KEY BOS DI SINI (Jangan lupa ya bos!)
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

  // ==== JURUS DETEKTIF: SCAN DAFTAR MESIN SERVER ====
  Future<void> _tanyaGemini() async {
    if (_geminiApiKey.isEmpty || _geminiApiKey == "MASUKKAN_API_KEY_GOOGLE_STUDIO_DI_SINI") {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("API Key belum diisi di dalam kode!")));
      return;
    }

    setState(() => _isAskingGemini = true);
    FocusScope.of(context).unfocus(); // Tutup keyboard

    try {
      // Kita panggil titik pusat server untuk meminta daftar nama mesin
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$_geminiApiKey');
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List models = data['models'] ?? [];
        
        // Kumpulkan semua nama mesin yang ada tulisan "gemini"
        String daftarMesin = "";
        for (var m in models) {
          String name = m['name']; // contoh hasilnya: models/gemini-pro
          if (name.contains("gemini")) {
             daftarMesin += "$name\n";
          }
        }

        // Tampilkan daftarnya ke layar bos
        if (mounted) {
          showDialog(
            context: context, 
            builder: (c) => AlertDialog(
              title: const Text("🔍 Mesin yang Tersedia:"),
              content: SingleChildScrollView(
                child: Text(daftarMesin.isEmpty ? "Tidak ada mesin gemini ditemukan" : daftarMesin, 
                  style: const TextStyle(fontSize: 14)
                )
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK, SIAP!"))
              ]
            )
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal intip server: ${response.statusCode}")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: Cek internet bos!")));
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