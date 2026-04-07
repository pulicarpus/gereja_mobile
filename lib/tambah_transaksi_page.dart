import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'user_manager.dart';

// --- KELAS BANTUAN UNTUK MODE EDIT ---
class TransaksiEditData {
  final String id;
  final String keterangan;
  final int jumlah;
  final String jenis;
  final DateTime? tanggal;
  final String? kategori;

  TransaksiEditData({
    required this.id,
    required this.keterangan,
    required this.jumlah,
    required this.jenis,
    this.tanggal,
    this.kategori,
  });
}

class TambahTransaksiPage extends StatefulWidget {
  final String? filterKategorial; // Tangkapan Kategori dari halaman sebelumnya
  final TransaksiEditData? transaksiEdit;

  const TambahTransaksiPage({super.key, this.filterKategorial, this.transaksiEdit});

  @override
  State<TambahTransaksiPage> createState() => _TambahTransaksiPageState();
}

class _TambahTransaksiPageState extends State<TambahTransaksiPage> {
  final _db = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();
  
  final _keteranganController = TextEditingController();
  final _jumlahController = TextEditingController();
  
  String _jenisTransaksi = "Pemasukan";
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  // VARIABEL KUNCI: Untuk menampung kategori (Umum, Pemuda, dll) sesuai logika Kotlin Bos
  String? _kategoriAktif; 

  @override
  void initState() {
    super.initState();
    
    // 1. Tangkap Kategori dari parameter
    _kategoriAktif = widget.filterKategorial;

    if (widget.transaksiEdit != null) {
      _setupEditMode();
    }
  }

  void _setupEditMode() {
    var trx = widget.transaksiEdit!;
    _keteranganController.text = trx.keterangan;
    _jumlahController.text = trx.jumlah.toString();
    _jenisTransaksi = trx.jenis;
    
    if (trx.tanggal != null) {
      _selectedDate = trx.tanggal!;
    }
    
    // Jika sedang edit, pastikan kategoriAktif mengikuti data yang diedit (Persis logika Kotlin)
    _kategoriAktif = trx.kategori;
  }

  @override
  void dispose() {
    _keteranganController.dispose();
    _jumlahController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF075E54),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) {
      _showSnack("Gagal menyimpan, ID Gereja tidak ditemukan.");
      return;
    }

    int jumlah = int.tryParse(_jumlahController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (jumlah <= 0) {
      _showSnack("Keterangan dan Jumlah harus diisi");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Pastikan kategori yang disimpan tidak kosong. Jika kosong, default ke "Umum"
      String kategoriSave = (_kategoriAktif == null || _kategoriAktif!.isEmpty) ? "Umum" : _kategoriAktif!;

      var collection = _db.collection("churches").doc(churchId).collection("transaksi");

      if (widget.transaksiEdit != null) {
        // --- MODE UPDATE ---
        await collection.doc(widget.transaksiEdit!.id).update({
          "keterangan": _keteranganController.text.trim(),
          "jumlah": jumlah,
          "jenis": _jenisTransaksi,
          "tanggal": Timestamp.fromDate(_selectedDate),
          "kategori": kategoriSave, // <--- SEKARANG KATEGORI DISIMPAN!
        });
        _showSnack("Berhasil diupdate di Kas $kategoriSave");
      } else {
        // --- MODE TAMBAH BARU ---
        await collection.add({
          "keterangan": _keteranganController.text.trim(),
          "jumlah": jumlah,
          "jenis": _jenisTransaksi,
          "tanggal": Timestamp.fromDate(_selectedDate),
          "kategori": kategoriSave, // <--- SEKARANG KATEGORI DISIMPAN!
        });
        _showSnack("Berhasil disimpan ke Kas $kategoriSave");
      }
      
      if (mounted) Navigator.pop(context, true); 
      
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
    bool isEdit = widget.transaksiEdit != null;
    String dateFormat = DateFormat('dd MMMM yyyy', 'id_ID').format(_selectedDate);
    String label = (_kategoriAktif == null || _kategoriAktif!.isEmpty) ? "Umum" : _kategoriAktif!;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(isEdit ? "Edit Transaksi" : "Catat Transaksi ($label)"),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // JENIS TRANSAKSI
                      const Text("Jenis Transaksi", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text("Pemasukan", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                              value: "Pemasukan",
                              groupValue: _jenisTransaksi,
                              activeColor: Colors.green,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (val) => setState(() => _jenisTransaksi = val!),
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text("Pengeluaran", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              value: "Pengeluaran",
                              groupValue: _jenisTransaksi,
                              activeColor: Colors.red,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (val) => setState(() => _jenisTransaksi = val!),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 30),

                      // KETERANGAN
                      const Text("Keterangan", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _keteranganController,
                        decoration: InputDecoration(
                          hintText: "Contoh: Beli Token Listrik",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        validator: (val) => val == null || val.isEmpty ? "Wajib diisi" : null,
                      ),
                      const SizedBox(height: 20),

                      // JUMLAH
                      const Text("Jumlah (Rp)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _jumlahController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _jenisTransaksi == "Pemasukan" ? Colors.green : Colors.red),
                        decoration: InputDecoration(
                          prefixText: "Rp ",
                          prefixStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _jenisTransaksi == "Pemasukan" ? Colors.green : Colors.red),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        validator: (val) => val == null || val.isEmpty ? "Wajib diisi" : null,
                      ),
                      const SizedBox(height: 20),

                      // TANGGAL
                      const Text("Tanggal", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () => _selectDate(context),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(10)),
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
              const SizedBox(height: 30),

              // TOMBOL SIMPAN
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF075E54),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isLoading ? null : _saveTransaction, // Sesuai nama fungsi Kotlin
                child: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(isEdit ? "UPDATE TRANSAKSI" : "SIMPAN TRANSAKSI", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}