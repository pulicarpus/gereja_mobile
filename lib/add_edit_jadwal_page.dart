import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'user_manager.dart';

class AddEditJadwalPage extends StatefulWidget {
  final String? jadwalId;
  final String? filterKategorial; // null = Umum, isi = Kategorial

  const AddEditJadwalPage({super.key, this.jadwalId, this.filterKategorial});

  @override
  State<AddEditJadwalPage> createState() => _AddEditJadwalPageState();
}

class _AddEditJadwalPageState extends State<AddEditJadwalPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final UserManager _userManager = UserManager();

  // Controller untuk input teks
  final _etNama = TextEditingController();
  final _etWaktu = TextEditingController(); // Untuk display Tanggal & Jam
  final _etTempat = TextEditingController();
  final _etDeskripsi = TextEditingController();
  
  // Controller khusus Pelayan (Sesuai map di Kotlin Bos)
  final _etWl = TextEditingController();
  final _etSinger = TextEditingController();
  final _etMusik = TextEditingController();
  final _etTamborin = TextEditingController();
  final _etPenerimaTamu = TextEditingController();

  DateTime _selectedDateTime = DateTime.now();
  bool _isEdit = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.jadwalId != null) {
      _isEdit = true;
      _loadDataForEdit();
    }
  }

  // --- LOAD DATA JIKA MODE EDIT ---
  Future<void> _loadDataForEdit() async {
    setState(() => _isLoading = true);
    String? churchId = _userManager.getChurchIdForCurrentView();
    var doc = await _db.collection("churches").doc(churchId)
        .collection("jadwal").doc(widget.jadwalId).get();

    if (doc.exists) {
      var data = doc.data()!;
      _etNama.text = data['namaKegiatan'] ?? "";
      _etTempat.text = data['tempat'] ?? "";
      _etDeskripsi.text = data['deskripsi'] ?? "";
      
      // Ambil Tanggal dari Firestore Timestamp
      if (data['tanggal'] != null) {
        _selectedDateTime = (data['tanggal'] as Timestamp).toDate();
        _etWaktu.text = DateFormat('yyyy-MM-dd HH:mm').format(_selectedDateTime);
      }

      // Ambil Map Pelayan (Sama seperti logika get("WL") di Kotlin)
      var p = data['pelayan'] as Map<String, dynamic>?;
      if (p != null) {
        _etWl.text = p['Worship Leader'] ?? "";
        _etSinger.text = p['Singer'] ?? "";
        _etMusik.text = p['Pemain Musik'] ?? "";
        _etTamborin.text = p['Tamborin'] ?? "";
        _etPenerimaTamu.text = p['Penerima Tamu'] ?? "";
      }
    }
    setState(() => _isLoading = false);
  }

  // --- FUNGSI PICKER TANGGAL & JAM ---
  Future<void> _pickDateTime() async {
    DateTime? date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (date != null) {
      TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
      );

      if (time != null) {
        setState(() {
          _selectedDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
          _etWaktu.text = DateFormat('yyyy-MM-dd HH:mm').format(_selectedDateTime);
        });
      }
    }
  }

  // --- FUNGSI SIMPAN KE FIRESTORE ---
  Future<void> _saveJadwal() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    String? churchId = _userManager.getChurchIdForCurrentView();

    // Mapping Data Pelayan (Sesuai Struktur Kotlin Bos)
    Map<String, String> pelayanMap = {
      "Worship Leader": _etWl.text.trim(),
      "Singer": _etSinger.text.trim(),
      "Pemain Musik": _etMusik.text.trim(),
      "Tamborin": _etTamborin.text.trim(),
      "Penerima Tamu": _etPenerimaTamu.text.trim(),
    };

    Map<String, dynamic> jadwalData = {
      "namaKegiatan": _etNama.text.trim(),
      "waktu": _etWaktu.text.trim(), // String format untuk display cepat
      "deskripsi": _etDeskripsi.text.trim(),
      "tempat": _etTempat.text.trim(),
      "pelayan": pelayanMap,
      "tanggal": Timestamp.fromDate(_selectedDateTime), // Timestamp asli untuk sorting
      "churchId": churchId,
      "kategoriKegiatan": widget.filterKategorial, // Penyelamat data kategorial
      "lastUpdate": FieldValue.serverTimestamp(),
    };

    try {
      var colRef = _db.collection("churches").doc(churchId).collection("jadwal");
      
      if (_isEdit) {
        await colRef.doc(widget.jadwalId).update(jadwalData);
      } else {
        await colRef.add(jadwalData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Jadwal Berhasil Disimpan!")));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e")));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? "Edit Jadwal" : (widget.filterKategorial ?? "Jadwal Umum")),
        actions: [
          if (!_isLoading) IconButton(onPressed: _saveJadwal, icon: const Icon(Icons.check_circle, size: 30))
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildField(_etNama, "Nama Kegiatan", Icons.event_note, true),
                const SizedBox(height: 15),
                
                // Field Waktu (Read Only, Klik untuk buka Picker)
                TextFormField(
                  controller: _etWaktu,
                  readOnly: true,
                  onTap: _pickDateTime,
                  decoration: InputDecoration(
                    labelText: "Tanggal & Jam",
                    prefixIcon: const Icon(Icons.calendar_month),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v!.isEmpty ? "Waktu wajib diisi" : null,
                ),
                
                const SizedBox(height: 15),
                _buildField(_etTempat, "Tempat / Lokasi", Icons.location_on, false),
                const SizedBox(height: 15),
                _buildField(_etDeskripsi, "Deskripsi Tambahan", Icons.description, false, maxLines: 3),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Row(children: [
                    Icon(Icons.groups, color: Colors.indigo),
                    SizedBox(width: 10),
                    Text("Petugas Pelayanan", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                ),

                // Group Pelayan (Dibuat lebih rapi dalam Card)
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 0,
                  color: Colors.grey[100],
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      children: [
                        _buildField(_etWl, "Worship Leader (WL)", Icons.mic, false),
                        const SizedBox(height: 10),
                        _buildField(_etSinger, "Singer", Icons.mic_external_on, false, maxLines: 2),
                        const SizedBox(height: 10),
                        _buildField(_etMusik, "Pemain Musik", Icons.music_note, false, maxLines: 2),
                        const SizedBox(height: 10),
                        _buildField(_etTamborin, "Tamborin / Penari", Icons.accessibility_new, false),
                        const SizedBox(height: 10),
                        _buildField(_etPenerimaTamu, "Penerima Tamu / Usher", Icons.front_hand, false),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: _saveJadwal,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  child: Text(_isEdit ? "PERBARUI JADWAL" : "SIMPAN JADWAL BARU"),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, bool mandatory, {int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: (v) => (mandatory && v!.isEmpty) ? "$label tidak boleh kosong" : null,
    );
  }
}