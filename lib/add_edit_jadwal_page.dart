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
  final _etDeskripsi = TextEditingController(); 
  
  // Controller khusus Pelayan
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
      
      if (data['tanggal'] != null) {
        _selectedDateTime = (data['tanggal'] as Timestamp).toDate();
        _etWaktu.text = DateFormat('yyyy-MM-dd HH:mm').format(_selectedDateTime);
      }

      var p = data['pelayan'] as Map<String, dynamic>?;
      if (p != null) {
        _etWl.text = p['Worship Leader'] ?? "";
        _etSinger.text = p['Singer'] ?? "";
        _etMusik.text = p['Pemain Musik'] ?? "";
        _etTamborin.text = p['Pemain Tamborin'] ?? p['Tamborin'] ?? "";
        _etLcd.text = p['Operator LCD'] ?? "";
        _etKolektan.text = p['Kolektan'] ?? "";
        _etDoaSyafaat.text = p['Doa Syafaat'] ?? "";
        _etPenerimaTamu.text = p['Penerima Tamu'] ?? "";
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _pickDateTime() async {
    FocusScope.of(context).unfocus(); 

    DateTime? date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.indigo,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      if (!mounted) return;
      TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: Colors.indigo)),
            child: child!,
          );
        },
      );

      if (time != null) {
        setState(() {
          _selectedDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
          _etWaktu.text = DateFormat('yyyy-MM-dd HH:mm').format(_selectedDateTime);
        });
      }
    }
  }

  Future<void> _saveJadwal() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    String? churchId = _userManager.getChurchIdForCurrentView();

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
      "deskripsi": _etDeskripsi.text.trim(), 
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Jadwal Berhasil Disimpan!"), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e"), backgroundColor: Colors.red));
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
      backgroundColor: const Color(0xFFF5F7FA), // Background abu-abu muda biar form pop-up
      appBar: AppBar(
        title: Text(_isEdit ? "Edit Jadwal" : "Tambah Jadwal", style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // --- KARTU 1: INFO UTAMA ---
                _buildSectionHeader("Informasi Utama", Icons.info_outline),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))]
                  ),
                  child: Column(
                    children: [
                      _buildField(_etNama, "Nama Kegiatan", Icons.event, true),
                      const SizedBox(height: 15),
                      
                      TextFormField(
                        controller: _etWaktu,
                        readOnly: true,
                        onTap: _pickDateTime,
                        decoration: InputDecoration(
                          labelText: "Waktu Pelaksanaan",
                          prefixIcon: Icon(Icons.access_time_filled, color: Colors.indigo.shade300),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.indigo.shade100)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.indigo.shade100)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
                        ),
                        validator: (v) => v!.isEmpty ? "Waktu wajib diisi" : null,
                      ),
                      
                      const SizedBox(height: 15),
                      _buildField(_etTempat, "Tempat", Icons.location_on, false),
                      const SizedBox(height: 15),
                      _buildField(_etDeskripsi, "Firman Tuhan", Icons.menu_book, false, isMultiline: true),
                    ],
                  ),
                ),
                
                const SizedBox(height: 25),

                // --- KARTU 2: DAFTAR PELAYAN ---
                _buildSectionHeader("Petugas Pelayanan", Icons.group),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))]
                  ),
                  child: Column(
                    children: [
                      _buildField(_etWl, "Worship Leader (WL)", Icons.mic_external_on, false),
                      const SizedBox(height: 12),
                      _buildField(_etSinger, "Singer (Pisahkan dengan koma)", Icons.queue_music, false, isMultiline: true),
                      const SizedBox(height: 12),
                      _buildField(_etMusik, "Pemain Musik", Icons.piano, false, isMultiline: true),
                      const SizedBox(height: 12),
                      _buildField(_etTamborin, "Tamborin", Icons.celebration, false, isMultiline: true),
                      const SizedBox(height: 12),
                      _buildField(_etLcd, "Operator LCD", Icons.desktop_mac, false),
                      const SizedBox(height: 12),
                      _buildField(_etKolektan, "Kolektan", Icons.volunteer_activism, false, isMultiline: true),
                      const SizedBox(height: 12),
                      _buildField(_etDoaSyafaat, "Doa Syafaat", Icons.front_hand, false, isMultiline: true),
                      const SizedBox(height: 12),
                      _buildField(_etPenerimaTamu, "Penerima Tamu", Icons.waving_hand, false, isMultiline: true),
                    ],
                  ),
                ),

                const SizedBox(height: 35),
                
                // --- TOMBOL SIMPAN SULTAN ---
                ElevatedButton.icon(
                  onPressed: _saveJadwal,
                  icon: const Icon(Icons.save, size: 24),
                  label: const Text("Simpan Jadwal", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 5,
                    shadowColor: Colors.indigo.withOpacity(0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                ),
                const SizedBox(height: 30), 
              ],
            ),
          ),
    );
  }

  // WIDGET HELPER: Header Bagian
  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.indigo, size: 22),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  // WIDGET HELPER: Input Field Modern
  Widget _buildField(TextEditingController controller, String label, IconData icon, bool mandatory, {bool isMultiline = false}) {
    return TextFormField(
      controller: controller,
      maxLines: isMultiline ? null : 1, 
      minLines: isMultiline ? 2 : 1, // Jika multiline, otomatis agak tinggi
      keyboardType: isMultiline ? TextInputType.multiline : TextInputType.text,
      textInputAction: isMultiline ? TextInputAction.newline : TextInputAction.next,
      textCapitalization: TextCapitalization.words, 
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade600),
        prefixIcon: Icon(icon, color: Colors.indigo.shade300), 
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), 
          borderSide: BorderSide(color: Colors.indigo.shade100)
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), 
          borderSide: BorderSide(color: Colors.indigo.shade100)
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), 
          borderSide: const BorderSide(color: Colors.indigo, width: 2)
        ),
      ),
      validator: (v) => (mandatory && v!.isEmpty) ? "$label tidak boleh kosong" : null,
    );
  }
}