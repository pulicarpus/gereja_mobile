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

  // Controller untuk input teks utama
  final _etNama = TextEditingController();
  final _etWaktu = TextEditingController(); 
  final _etTempat = TextEditingController();
  final _etDeskripsi = TextEditingController(); // Untuk Firman Tuhan
  
  // Controller khusus Pelayan (Lengkap sesuai screenshot)
  final _etWl = TextEditingController();
  final _etSinger = TextEditingController();
  final _etMusik = TextEditingController();
  final _etTamborin = TextEditingController();
  final _etLcd = TextEditingController();
  final _etKolektan = TextEditingController();
  final _etDoaSyafaat = TextEditingController();
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

  // ==== WAJIB ADA: Mencegah Memory Leak ====
  @override
  void dispose() {
    _etNama.dispose();
    _etWaktu.dispose();
    _etTempat.dispose();
    _etDeskripsi.dispose();
    _etWl.dispose();
    _etSinger.dispose();
    _etMusik.dispose();
    _etTamborin.dispose();
    _etLcd.dispose();
    _etKolektan.dispose();
    _etDoaSyafaat.dispose();
    _etPenerimaTamu.dispose();
    super.dispose();
  }
  // ==========================================

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

      // Ambil Map Pelayan
      var p = data['pelayan'] as Map<String, dynamic>?;
      if (p != null) {
        _etWl.text = p['Worship Leader'] ?? "";
        _etSinger.text = p['Singer'] ?? "";
        _etMusik.text = p['Pemain Musik'] ?? "";
        // Mendukung data lama ('Tamborin') atau data baru ('Pemain Tamborin')
        _etTamborin.text = p['Pemain Tamborin'] ?? p['Tamborin'] ?? "";
        _etLcd.text = p['Operator LCD'] ?? "";
        _etKolektan.text = p['Kolektan'] ?? "";
        _etDoaSyafaat.text = p['Doa Syafaat'] ?? "";
        _etPenerimaTamu.text = p['Penerima Tamu'] ?? "";
      }
    }
    setState(() => _isLoading = false);
  }

  // --- FUNGSI PICKER TANGGAL & JAM ---
  Future<void> _pickDateTime() async {
    FocusScope.of(context).unfocus(); // Sembunyikan keyboard

    DateTime? date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (date != null) {
      if (!mounted) return;
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

    // Mapping Data Pelayan dengan Key yang benar
    Map<String, String> pelayanMap = {
      "Worship Leader": _etWl.text.trim(),
      "Singer": _etSinger.text.trim(),
      "Pemain Musik": _etMusik.text.trim(),
      "Pemain Tamborin": _etTamborin.text.trim(),
      "Operator LCD": _etLcd.text.trim(),
      "Kolektan": _etKolektan.text.trim(),
      "Doa Syafaat": _etDoaSyafaat.text.trim(),
      "Penerima Tamu": _etPenerimaTamu.text.trim(),
    };

    Map<String, dynamic> jadwalData = {
      "namaKegiatan": _etNama.text.trim(),
      "waktu": _etWaktu.text.trim(), 
      "deskripsi": _etDeskripsi.text.trim(), // Sekarang untuk Firman Tuhan
      "tempat": _etTempat.text.trim(),
      "pelayan": pelayanMap,
      "tanggal": Timestamp.fromDate(_selectedDateTime), 
      "churchId": churchId,
      "kategoriKegiatan": widget.filterKategorial, 
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
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? "Edit Jadwal" : "Tambah Jadwal"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          if (!_isLoading) 
            IconButton(
              onPressed: _saveJadwal, 
              icon: const Icon(Icons.check, color: Colors.blue, size: 28)
            )
        ],
      ),
      backgroundColor: Colors.white, // Latar belakang disesuaikan screenshot
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildField(_etNama, "Nama Kegiatan", null, true),
                const SizedBox(height: 15),
                
                // Field Waktu (Read Only, Klik untuk buka Picker)
                TextFormField(
                  controller: _etWaktu,
                  readOnly: true,
                  onTap: _pickDateTime,
                  decoration: const InputDecoration(
                    labelText: "Waktu (Cth: yyyy-MM-dd HH:mm)",
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v!.isEmpty ? "Waktu wajib diisi" : null,
                ),
                
                const SizedBox(height: 15),
                _buildField(_etTempat, "Tempat", null, false),
                const SizedBox(height: 15),
                
                // Ganti label menjadi Deskripsi / Firman Tuhan (Multiline)
                _buildField(_etDeskripsi, "Deskripsi / Firman Tuhan", null, false, isMultiline: true),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text("Pelayan Ibadah", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                ),

                _buildField(_etWl, "Worship Leader (WL)", null, false),
                const SizedBox(height: 10),
                _buildField(_etSinger, "Singer", null, false, isMultiline: true),
                const SizedBox(height: 10),
                _buildField(_etMusik, "Pemain Musik", null, false, isMultiline: true),
                const SizedBox(height: 10),
                _buildField(_etTamborin, "Pemain Tamborin", null, false, isMultiline: true),
                const SizedBox(height: 10),
                _buildField(_etLcd, "Operator LCD", null, false),
                const SizedBox(height: 10),
                _buildField(_etKolektan, "Kolektan", null, false, isMultiline: true),
                const SizedBox(height: 10),
                _buildField(_etDoaSyafaat, "Doa Syafaat", null, false, isMultiline: true),
                const SizedBox(height: 10),
                _buildField(_etPenerimaTamu, "Penerima Tamu", null, false, isMultiline: true),

                const SizedBox(height: 30),
                
                // Tombol biru "Simpan Jadwal" di bawah sesuai screenshot
                ElevatedButton(
                  onPressed: _saveJadwal,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))
                  ),
                  child: const Text("Simpan Jadwal", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                const SizedBox(height: 20), 
              ],
            ),
          ),
    );
  }

  // FUNGSI HELPER: isMultiline = true membuat user bisa tekan "Enter" untuk baris baru
  Widget _buildField(TextEditingController controller, String label, IconData? icon, bool mandatory, {bool isMultiline = false}) {
    return TextFormField(
      controller: controller,
      // Jika isMultiline true, maxLines null agar bisa melar ke bawah. Jika false, maxLines 1.
      maxLines: isMultiline ? null : 1, 
      keyboardType: isMultiline ? TextInputType.multiline : TextInputType.text,
      textInputAction: isMultiline ? TextInputAction.newline : TextInputAction.next,
      textCapitalization: TextCapitalization.words, 
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon) : null, // Icon dihilangkan sesuai screenshot, kecuali di-pass
        border: const OutlineInputBorder(), // Garis kotak standar
      ),
      validator: (v) => (mandatory && v!.isEmpty) ? "$label tidak boleh kosong" : null,
    );
  }
}