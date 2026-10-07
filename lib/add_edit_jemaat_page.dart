import 'upload_support.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'user_manager.dart';
import 'app_safety.dart';
import 'kategorial_config.dart';

class AddEditJemaatPage extends StatefulWidget {
  final Map<String, dynamic>? jemaatData; // Jika null = Tambah, Jika isi = Edit
  final String? idKepalaKeluargaBaru; // Untuk tambah anggota keluarga baru
  final String? initialKelompok;

  const AddEditJemaatPage({
    super.key,
    this.jemaatData,
    this.idKepalaKeluargaBaru,
    this.initialKelompok,
  });

  @override
  State<AddEditJemaatPage> createState() => _AddEditJemaatPageState();
}

class _AddEditJemaatPageState extends State<AddEditJemaatPage> {
  final String? _openedChurchId = UserManager().getChurchIdForCurrentView();
  final _formKey = GlobalKey<FormState>();
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  bool _isSaving = false;
  String? _newJemaatId;

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
  String _statusKeluarga = "Belum Diatur";

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
      _namaController.text = legacyText(d['namaLengkap']);
      _tglLahirController.text = d['tanggalLahir'] is Timestamp
          ? DateFormat('dd-MM-yyyy').format((d['tanggalLahir'] as Timestamp).toDate())
          : legacyText(d['tanggalLahir']);
      _alamatController.text = legacyText(d['alamat']);
      _noTelpController.text = legacyText(d['nomorTelepon']);
      _karuniaController.text = legacyText(d['karuniaPelayanan']);
      _catatanController.text = legacyText(d['catatanTambahan']);
      _existingPhotoUrl = d['fotoProfil']?.toString();
      _jenisKelamin = ['Pria', 'Wanita'].contains(d['jenisKelamin']) ? d['jenisKelamin'].toString() : 'Pria';
      _statusNikah = ['Belum Menikah', 'Menikah', 'Janda/Duda'].contains(d['statusPernikahan']) ? d['statusPernikahan'].toString() : 'Belum Menikah';
      _statusBaptis = ['Belum', 'Sudah'].contains(d['statusBaptis']) ? d['statusBaptis'].toString() : 'Belum';
      _kelompok = KategorialConfig.canonicalJemaat(d['kelompok']);
      _statusKeluarga = legacyText(d['statusKeluarga'], 'Belum Diatur');
    } else if (widget.initialKelompok != null) {
      _kelompok = KategorialConfig.canonicalJemaat(widget.initialKelompok);
    }
    
    // Logika Status Keluarga jika menambah anggota dari list keluarga
    // Hubungan keluarga selain Kepala Keluarga ditetapkan dari Menu Keluarga.
    // Form biodata umum tidak boleh memindahkan/mengubah relasi keluarga secara tidak sengaja.
    if (widget.idKepalaKeluargaBaru != null) {
      _statusKeluarga = "Anak";
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (picked != null && mounted) {
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
    if (picked != null && mounted) {
      _tglLahirController.text = DateFormat('dd-MM-yyyy').format(picked);
    }
  }

  Future<void> _validateAndSave() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    String? churchId = _openedChurchId;
    String? photoUrl = _existingPhotoUrl;
    if (churchId == null || churchId.isEmpty) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data gereja tidak valid.")));
      }
      return;
    }

    try {
      final access = await ChurchWriteAccess.check(churchId);
      if (!mounted) return;
      // 1. Upload Foto jika ada yang baru
      if (_imageFile != null) {
        String fileName = "${widget.jemaatData?['id'] ?? 'baru'}_${DateTime.now().microsecondsSinceEpoch}";
        Reference ref = _storage.ref().child("churches/$churchId/foto_jemaat/$fileName.jpg");
        await ref.putFile(_imageFile!, await prepareUpload(_imageFile!)).timeout(const Duration(seconds: 30));
        photoUrl = await ref.getDownloadURL().timeout(const Duration(seconds: 20));
      }

      // 2. Siapkan Map Data (Sesuai Firestore Bos)
      final jemaatMap = {
        "namaLengkap": _namaController.text.trim(),
        if (widget.jemaatData == null || _imageFile != null) "fotoProfil": photoUrl,
        if (_imageFile != null) "photoBase64": null,
        "jenisKelamin": _jenisKelamin,
        "tanggalLahir": _tglLahirController.text,
        "alamat": _alamatController.text.trim(),
        "nomorTelepon": _noTelpController.text.trim(),
        "statusPernikahan": _statusNikah,
        if (widget.jemaatData == null && widget.idKepalaKeluargaBaru != null) "statusKeluarga": _statusKeluarga,
        "statusBaptis": _statusBaptis,
        "kelompok": _kelompok,
        "karuniaPelayanan": _karuniaController.text,
        "catatanTambahan": _catatanController.text,
        "updatedAt": FieldValue.serverTimestamp(),
      };

      final colRef = _db.collection("churches").doc(churchId).collection("jemaat");

      if (widget.jemaatData != null) {
        final jemaatId = widget.jemaatData!['id']?.toString().trim() ?? "";
        if (jemaatId.isEmpty) {
          throw StateError("ID jemaat tidak valid");
        }

        final jemaatRef = colRef.doc(jemaatId);
        await _db.runTransaction((tx) async {
          await access.inTransaction(tx);
          final fresh = await tx.get(jemaatRef);
          if (!fresh.exists) throw StateError('Data jemaat sudah dihapus.');
          final book = fresh.data()!;
          final expected = widget.jemaatData!;
          for (final key in ['uid', 'kelompok', 'updatedAt']) {
            if (book[key] != expected[key]) throw StateError('Data jemaat berubah. Muat ulang dahulu.');
          }
          final linkedUid = legacyText(book['uid']).trim();
          final userRef = linkedUid.isEmpty ? null : _db.collection('users').doc(linkedUid);
          final account = userRef == null ? null : await tx.get(userRef);
          assertBookOwner(book, account?.data(), churchId, jemaatId);
          access.assertCurrent();
          tx.update(jemaatRef, jemaatMap);
          if (userRef != null && !KategorialConfig.same(book['kelompok'], _kelompok)) {
            tx.update(userRef, {'kelompok': _kelompok, 'isPengurus': false});
          }
        }).timeout(const Duration(seconds: 20));
      } else {
        final docRef = colRef.doc(_newJemaatId ??= colRef.doc().id);
        jemaatMap['id'] = docRef.id;
        if (widget.idKepalaKeluargaBaru != null) {
          jemaatMap['idKepalaKeluarga'] = widget.idKepalaKeluargaBaru;
        }
        await _db.runTransaction((tx) async {
          await access.inTransaction(tx);
          final existing = await tx.get(docRef);
          if (widget.idKepalaKeluargaBaru != null) {
            final head = await tx.get(colRef.doc(widget.idKepalaKeluargaBaru));
            if (!head.exists || head.data()?['statusKeluarga'] != 'Kepala Keluarga') {
              throw StateError('Kepala keluarga berubah. Buka ulang keluarga.');
            }
          }
          access.assertCurrent();
          if (existing.exists) {
            assertRetryMatches(existing.data()!, jemaatMap);
          } else {
            tx.set(docRef, jemaatMap);
          }
        }).timeout(const Duration(seconds: 20));
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
  void dispose() {
    _namaController.dispose();
    _tglLahirController.dispose();
    _alamatController.dispose();
    _noTelpController.dispose();
    _karuniaController.dispose();
    _catatanController.dispose();
    super.dispose();
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
                  validator: (v) => (v ?? '').trim().isEmpty ? "Wajib diisi" : null
                ),
                const SizedBox(height: 15),

                _buildDropdown("Jenis Kelamin", ["Pria", "Wanita"], _jenisKelamin, (v) => setState(() => _jenisKelamin = v!)),
                _buildDropdown(
                  "Kelompok",
                  KategorialConfig.pilihanJemaat,
                  _kelompok,
                  (v) => setState(() => _kelompok = v!),
                ),
                if (widget.idKepalaKeluargaBaru != null)
                  _buildDropdown("Hubungan Keluarga", ["Istri", "Anak", "Ayah", "Ibu"], _statusKeluarga, (v) => setState(() => _statusKeluarga = v!))
                else if (widget.jemaatData != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: "Hubungan Keluarga",
                        border: OutlineInputBorder(),
                        helperText: "Ubah hubungan melalui menu Keluarga.",
                      ),
                      child: Text(_statusKeluarga, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                
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
        value: items.contains(current) ? current : items.first,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
      ),
    );
  }
}
