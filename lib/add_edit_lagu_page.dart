import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

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

  final _etScraperUrl = TextEditingController();
  final _etJudul = TextEditingController();
  final _etNomor = TextEditingController();
  final _etPencipta = TextEditingController();
  final _etLirik = TextEditingController();
  
  String _selectedKategori = "NKI";
  bool _isLoading = false;
  bool _isScraping = false;

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
    _etScraperUrl.dispose();
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

  // ==== JURUS RAHASIA: WEB SCRAPER LIRIK ====
  Future<void> _sedotLirik() async {
    String url = _etScraperUrl.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Masukkan link lirik dulu, Bos!")));
      return;
    }

    setState(() => _isScraping = true);
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        dom.Document doc = html_parser.parse(response.body);
        
        // Logika khusus untuk liriklagukristen.id
        if (url.contains("liriklagukristen.id")) {
          String rawTitle = doc.querySelector("h1.entry-title")?.text ?? "";
          // Biasanya formatnya: Lirik Lagu [Judul] - [Pencipta]
          _etJudul.text = rawTitle.replaceAll("Lirik Lagu", "").split("-")[0].trim();
          if (rawTitle.contains("-")) {
            _etPencipta.text = rawTitle.split("-")[1].trim();
          }
          
          // Ambil isi lirik di dalam entry-content
          var entryContent = doc.querySelector(".entry-content");
          entryContent?.querySelectorAll("script").forEach((s) => s.remove());
          entryContent?.querySelectorAll("ins").forEach((i) => i.remove());
          
          _etLirik.text = entryContent?.text.trim() ?? "";
        } 
        // Logika umum (Fallback)
        else {
          _etJudul.text = doc.querySelector("h1")?.text.trim() ?? "";
          _etLirik.text = doc.querySelector("article")?.text.trim() ?? doc.body?.text.trim() ?? "";
        }

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lirik berhasil disedot!")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal sedot: $e")));
    } finally {
      setState(() => _isScraping = false);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.songId == null ? "Tambah Lagu" : "Edit Lagu"),
        actions: [
          if (!_isLoading) IconButton(onPressed: _saveLagu, icon: const Icon(Icons.save))
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // PANEL SCRAPER
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200)
                  ),
                  child: Column(
                    children: [
                      const Text("Sedot Lirik dari Web", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _etScraperUrl,
                              decoration: const InputDecoration(
                                hintText: "Tempel link lirik di sini...",
                                isDense: true,
                                border: OutlineInputBorder()
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _isScraping 
                            ? const CircularProgressIndicator()
                            : IconButton.filled(
                                onPressed: _sedotLirik, 
                                icon: const Icon(Icons.bolt),
                                tooltip: "Sedot sekarang",
                              )
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),

                // FORM UTAMA
                _buildField(_etJudul, "Judul Lagu", true),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(child: _buildField(_etNomor, "Nomor (Opsional)", false)),
                    const SizedBox(width: 15),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedKategori,
                        decoration: const InputDecoration(labelText: "Kategori", border: OutlineInputBorder()),
                        items: ["NKI", "KONTEMPORER"].map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                        onChanged: (v) => setState(() => _selectedKategori = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                _buildField(_etPencipta, "Pencipta / Artis", false),
                const SizedBox(height: 15),
                _buildField(_etLirik, "Isi Lirik", true, maxLines: 15),
                const SizedBox(height: 30),
                
                ElevatedButton(
                  onPressed: _saveLagu,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50)
                  ),
                  child: const Text("SIMPAN KE DATABASE"),
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
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      validator: (v) => (mandatory && v!.isEmpty) ? "$label wajib diisi" : null,
    );
  }
}