import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'user_manager.dart';

class AddEditJemaatPage extends StatefulWidget {
  final Map<String, dynamic>? jemaatData; // Jika null = Tambah, Jika isi = Edit
  final String? idKepalaKeluargaBaru; // Untuk tambah anggota keluarga baru

  const AddEditJemaatPage({super.key, this.jemaatData, this.idKepalaKeluargaBaru});

  @override
  State<AddEditJemaatPage> createState() => _AddEditJemaatPageState();
}

class _AddEditJemaatPageState extends State<AddEditJemaatPage> {
  final _formKey = GlobalKey<FormState>();
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  bool _isSaving = false;

  // Controllers sesuai aplikasi Kotlin lama Bos
  final _namaController = TextEditingController();
  final _tglLahirController = TextEditingController();
  final _alamatController = TextEditingController();
  final _noTelpController = TextEditingController();
  final _karuniaController = TextEditingController();
  final _catatanController = TextEditingController();

  // Dropdown Values
  String _jenisKelamin = "Pria";
  String _statusNikah = "Belum Menikah";
  String _statusBaptis = "Belum";
  String _kelompok = "Lainnya";
  String _statusKeluarga = "Kepala Keluarga";

  File? _imageFile;
  String? _existingPhotoUrl;

  @override
  void initState() {
    super.initState();
    _setupInitialData();
  }

  void _setupInitialData() {
    if (widget.jemaatData != null) {
      final d = widget.jemaatData!;
      _namaController.text = d['namaLengkap'] ?? "";
      _tglLahirController.text = d['tanggalLahir'] ?? "";
      _alamatController.text = d['alamat'] ?? "";
      _noTelpController.text = d['nomorTelepon'] ?? "";
      _karuniaController.text = d['karuniaPelayanan'] ?? "";
      _catatanController.text = d['catatanTambahan'] ?? "";
      _existingPhotoUrl = d['fotoProfil'];
      _jenisKelamin = d['jenisKelamin'] ?? "Pria";
      _statusNikah = d['statusPernikahan'] ?? "Belum Menikah";
      _statusBaptis = d['statusBaptis'] ?? "Belum";
      _kelompok = d['kelompok'] ?? "Lainnya";
      _statusKeluarga = d['statusKeluarga'] ?? "Kepala Keluarga";
    }
    
    // Logika Status Keluarga jika menambah anggota dari list keluarga
    if (widget.idKepalaKeluargaBaru != null) {
      _statusKeluarga = "Anak"; 
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _selectDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _tglLahirController.text = DateFormat('dd-MM-yyyy').format(picked);
    }
  }

  Future<void> _validateAndSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    String? churchId = UserManager().getChurchIdForCurrentView();
    String? photoUrl = _existingPhotoUrl;

    try {
      // 1. Upload Foto jika ada yang baru
      if (_imageFile != null) {
        String fileName = widget.jemaatData?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
        Reference ref = _storage.ref().child("churches/$churchId/foto_jemaat/$fileName.jpg");
        await ref.putFile(_imageFile!);
        photoUrl = await ref.getDownloadURL();
      }

      // 2. Siapkan Map Data (Sesuai Firestore Bos)
      final jemaatMap = {
        "namaLengkap": _namaController.text.trim(),
        "fotoProfil": photoUrl,
        "photoBase64": null,
        "jenisKelamin": _jenisKelamin,
        "tanggalLahir": _tglLahirController.text,
        "alamat": _alamatController.text,
        "nomorTelepon": _noTelpController.text,
        "statusPernikahan": _statusNikah,
        "statusKeluarga": _statusKeluarga,
        "statusBaptis": _statusBaptis,
        "kelompok": _kelompok,
        "karuniaPelayanan": _karuniaController.text,
        "catatanTambahan": _catatanController.text,
        "updatedAt": FieldValue.serverTimestamp(),
      };

      final colRef = _db.collection("churches").doc(churchId).collection("jemaat");

      if (widget.jemaatData != null) {
        // UPDATE (Dulu pakai .document, sekarang pakai .doc agar lolos GitHub)
        await colRef.doc(widget.jemaatData!['id']).update(jemaatMap);
      } else {
        // TAMBAH BARU
        if (_statusKeluarga != "Kepala Keluarga") {
          jemaatMap["idKepalaKeluarga"] = widget.idKepalaKeluargaBaru;
        }

        DocumentReference docRef = await colRef.add(jemaatMap);
        String newId = docRef.id;
        
        // Update ID dokumen ke dalam field 'id' (Sinkron dengan Kotlin lama)
        await docRef.update({"id": newId});
        
        if (_statusKeluarga == "Kepala Keluarga") {
          await docRef.update({"idKepalaKeluarga": newId});
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.jemaatData == null ? "Tambah Jemaat" : "Edit Jemaat")),
      body: _isSaving 
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: _imageFile != null 
                        ? FileImage(_imageFile!) 
                        : (_existingPhotoUrl != null ? NetworkImage(_existingPhotoUrl!) : null) as ImageProvider?,
                      child: (_imageFile == null && _existingPhotoUrl == null) ? const Icon(Icons.camera_alt, size: 40) : null,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                TextFormField(
                  controller: _namaController, 
                  decoration: const InputDecoration(labelText: "Nama Lengkap *", border: OutlineInputBorder()),
                  validator: (v) => v!.isEmpty ? "Wajib diisi" : null
                ),
                const SizedBox(height: 15),

                _buildDropdown("Jenis Kelamin", ["Pria", "Wanita"], _jenisKelamin, (v) => setState(() => _jenisKelamin = v!)),
                _buildDropdown("Kelompok", ["Sekolah Minggu", "Pemuda Remaja", "Perkawan", "Perkaria", "Lainnya"], _kelompok, (v) => setState(() => _kelompok = v!)),
                _buildDropdown("Status Keluarga", ["Kepala Keluarga", "Istri", "Anak"], _statusKeluarga, (v) => setState(() => _statusKeluarga = v!)),
                
                const SizedBox(height: 15),
                TextFormField(
                  controller: _tglLahirController, 
                  readOnly: true, 
                  onTap: _selectDate, 
                  decoration: const InputDecoration(labelText: "Tanggal Lahir", border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today))
                ),
                const SizedBox(height: 15),
                TextFormField(controller: _alamatController, decoration: const InputDecoration(labelText: "Alamat", border: OutlineInputBorder())),
                const SizedBox(height: 15),
                TextFormField(controller: _noTelpController, decoration: const InputDecoration(labelText: "Nomor Telepon", border: OutlineInputBorder()), keyboardType: TextInputType.phone),
                
                _buildDropdown("Status Pernikahan", ["Belum Menikah", "Menikah", "Janda/Duda"], _statusNikah, (v) => setState(() => _statusNikah = v!)),
                _buildDropdown("Status Baptis", ["Sudah", "Belum"], _statusBaptis, (v) => setState(() => _statusBaptis = v!)),

                const SizedBox(height: 15),
                TextFormField(controller: _karuniaController, decoration: const InputDecoration(labelText: "Karunia Pelayanan", border: OutlineInputBorder())),
                const SizedBox(height: 15),
                TextFormField(controller: _catatanController, maxLines: 3, decoration: const InputDecoration(labelText: "Catatan Tambahan", border: OutlineInputBorder())),
                
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: _validateAndSave,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text("SIMPAN DATA JEMAAT", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 50),
              ],
            ),
          ),
    );
  }

  Widget _buildDropdown(String label, List<String> items, String current, Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButtonFormField<String>(
        value: current,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
      ),
    );
  }
}