import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'user_manager.dart';

// --- KELAS BANTUAN UNTUK MODE EDIT ---
class PerpuluhanEditData {
  final String id;
  final int jumlah;
  final String? jemaatId;
  final String? namaJemaat;
  final DateTime? tanggal;

  PerpuluhanEditData({
    required this.id,
    required this.jumlah,
    this.jemaatId,
    this.namaJemaat,
    this.tanggal,
  });
}

class TambahPerpuluhanPage extends StatefulWidget {
  final PerpuluhanEditData? perpuluhanEdit;

  const TambahPerpuluhanPage({super.key, this.perpuluhanEdit});

  @override
  State<TambahPerpuluhanPage> createState() => _TambahPerpuluhanPageState();
}

class _TambahPerpuluhanPageState extends State<TambahPerpuluhanPage> {
  final _db = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();
  
  final _jumlahController = TextEditingController();
  final _namaLuarController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  
  List<Map<String, dynamic>> _jemaatList = [];
  String? _selectedJemaatId;
  
  bool _isJemaatLuar = false;
  bool _isLoading = false;
  bool _isFetchingJemaat = false;

  @override
  void initState() {
    super.initState();
    
    // Cek apakah ini Mode Edit
    if (widget.perpuluhanEdit != null) {
      _setupEditMode();
    } else {
      _loadJemaatData();
    }
  }

  @override
  void dispose() {
    _jumlahController.dispose();
    _namaLuarController.dispose();
    super.dispose();
  }

  void _setupEditMode() {
    var data = widget.perpuluhanEdit!;
    _jumlahController.text = data.jumlah.toString();
    if (data.tanggal != null) {
      _selectedDate = data.tanggal!;
    }
    // Jika tidak ada ID Jemaat, berarti dia Jemaat Luar
    if (data.jemaatId == null) {
      _isJemaatLuar = true;
      _namaLuarController.text = data.namaJemaat ?? "";
    } else {
      // Kita masukkan data jemaat ke list sementara agar dropdown tetap terisi nama dia
      _jemaatList = [{'id': data.jemaatId, 'namaLengkap': data.namaJemaat}];
      _selectedJemaatId = data.jemaatId;
    }
  }

  Future<void> _loadJemaatData() async {
    setState(() => _isFetchingJemaat = true);
    String? churchId = UserManager().activeChurchId;
    
    if (churchId == null) {
      _showSnack("ID Gereja tidak ditemukan.");
      setState(() => _isFetchingJemaat = false);
      return;
    }

    try {
      var snap = await _db.collection("churches").doc(churchId).collection("jemaat")
          .orderBy("namaLengkap")
          .get();
          
      List<Map<String, dynamic>> tempList = [];
      for (var doc in snap.docs) {
        var data = doc.data();
        tempList.add({
          'id': doc.id,
          'namaLengkap': data['namaLengkap'] ?? "Tanpa Nama",
        });
      }
      
      setState(() {
        _jemaatList = tempList;
      });
    } catch (e) {
      _showSnack("Gagal memuat data jemaat: $e");
    } finally {
      setState(() => _isFetchingJemaat = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)), // Bisa maju 1 tahun
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF075E54), // Warna header kalender
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _savePerpuluhan() async {
    if (!_formKey.currentState!.validate()) return;
    
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) {
      _showSnack("Gagal menyimpan, ID Gereja tidak ditemukan.");
      return;
    }

    int jumlah = int.tryParse(_jumlahController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (jumlah <= 0) {
      _showSnack("Jumlah harus lebih dari Rp 0");
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (widget.perpuluhanEdit != null) {
        // --- MODE UPDATE ---
        String namaUpdate = widget.perpuluhanEdit!.namaJemaat ?? "Amplop Tanpa Nama";
        if (_isJemaatLuar) {
          namaUpdate = _namaLuarController.text.trim().isEmpty ? "Amplop Tanpa Nama" : _namaLuarController.text.trim();
        }

        await _db.collection("churches").doc(churchId).collection("perpuluhan").doc(widget.perpuluhanEdit!.id).update({
          "jumlah": jumlah,
          "tanggal": Timestamp.fromDate(_selectedDate),
          if (_isJemaatLuar) "namaJemaat": namaUpdate,
        });
        
        _showSnack("Data berhasil diupdate");
      } else {
        // --- MODE TAMBAH BARU ---
        String? jemaatIdSave;
        String namaJemaatSave;

        if (_isJemaatLuar) {
          jemaatIdSave = null;
          namaJemaatSave = _namaLuarController.text.trim().isEmpty ? "Amplop Tanpa Nama" : _namaLuarController.text.trim();
        } else {
          if (_selectedJemaatId == null) {
            _showSnack("Pilih jemaat dari daftar!");
            setState(() => _isLoading = false);
            return;
          }
          var selectedJemaat = _jemaatList.firstWhere((element) => element['id'] == _selectedJemaatId);
          jemaatIdSave = selectedJemaat['id'];
          namaJemaatSave = selectedJemaat['namaLengkap'];
        }

        await _db.collection("churches").doc(churchId).collection("perpuluhan").add({
          "jumlah": jumlah,
          "jemaatId": jemaatIdSave,
          "namaJemaat": namaJemaatSave,
          "tanggal": Timestamp.fromDate(_selectedDate),
        });
        
        _showSnack("Data berhasil disimpan");
      }
      
      if (mounted) Navigator.pop(context, true); // Mengirim sinyal refresh ke halaman sebelumnya
      
    } catch (e) {
      _showSnack("Gagal menyimpan: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    bool isEdit = widget.perpuluhanEdit != null;
    String dateFormat = DateFormat('dd MMMM yyyy', 'id_ID').format(_selectedDate);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(isEdit ? "Edit Perpuluhan" : "Catat Perpuluhan"),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
      ),
      body: _isFetchingJemaat 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    
                    // CARD: JUMLAH & TANGGAL
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Jumlah Perpuluhan (Rp)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _jumlahController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
                              decoration: InputDecoration(
                                prefixText: "Rp ",
                                prefixStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                              ),
                              validator: (val) => val == null || val.isEmpty ? "Jumlah tidak boleh kosong" : null,
                            ),
                            const SizedBox(height: 20),
                            const Text("Tanggal Masuk", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                            const SizedBox(height: 10),
                            InkWell(
                              onTap: () => _selectDate(context),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade400),
                                  borderRadius: BorderRadius.circular(10)
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(dateFormat, style: const TextStyle(fontSize: 16)),
                                    const Icon(Icons.calendar_today, color: Color(0xFF075E54)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),

                    // CARD: DATA JEMAAT
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Penyetor", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 16)),
                            const SizedBox(height: 10),
                            
                            // Checkbox Jemaat Luar (Sembunyikan saat Edit Mode sesuai logika Kotlin)
                            if (!isEdit)
                              CheckboxListTile(
                                title: const Text("Jemaat Luar / Amplop Tanpa Nama"),
                                value: _isJemaatLuar,
                                activeColor: const Color(0xFF075E54),
                                contentPadding: EdgeInsets.zero,
                                controlAffinity: ListTileControlAffinity.leading,
                                onChanged: (val) {
                                  setState(() {
                                    _isJemaatLuar = val ?? false;
                                    if (_isJemaatLuar) _selectedJemaatId = null;
                                  });
                                },
                              ),
                            
                            // Dropdown Jemaat Lokal
                            if (!_isJemaatLuar)
                              DropdownButtonFormField<String>(
                                value: _selectedJemaatId,
                                hint: const Text("Pilih Jemaat"),
                                isExpanded: true,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 15),
                                ),
                                items: _jemaatList.map((jemaat) {
                                  return DropdownMenuItem<String>(
                                    value: jemaat['id'],
                                    child: Text(jemaat['namaLengkap']),
                                  );
                                }).toList(),
                                // Jika mode edit, kita kunci dropdownnya
                                onChanged: isEdit ? null : (val) {
                                  setState(() => _selectedJemaatId = val);
                                },
                                validator: (val) => val == null && !_isJemaatLuar ? "Wajib pilih jemaat" : null,
                              ),
                              
                            // Input Jemaat Luar
                            if (_isJemaatLuar)
                              TextFormField(
                                controller: _namaLuarController,
                                enabled: !isEdit, // Kunci input jika mode edit dan merupakan jemaat luar
                                decoration: InputDecoration(
                                  labelText: "Nama Penyetor (Opsional)",
                                  hintText: "Kosongkan untuk Amplop Tanpa Nama",
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // TOMBOL SIMPAN
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF075E54),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 3,
                      ),
                      onPressed: _isLoading ? null : _savePerpuluhan,
                      child: _isLoading 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(isEdit ? "UPDATE DATA" : "SIMPAN PERPULUHAN", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}