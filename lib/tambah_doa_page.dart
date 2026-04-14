import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'user_manager.dart';
import 'secrets.dart'; // 👇 Pastikan ini di-import untuk membaca osRestKeySecret
import 'loading_sultan.dart';

class TambahDoaPage extends StatefulWidget {
  final String? doaId;
  final Map<String, dynamic>? existingData;

  const TambahDoaPage({super.key, this.doaId, this.existingData});

  @override
  State<TambahDoaPage> createState() => _TambahDoaPageState();
}

class _TambahDoaPageState extends State<TambahDoaPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserManager _userManager = UserManager();

  final TextEditingController _etIsiDoa = TextEditingController();
  
  bool _isPrivat = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Kalau ada data lama (Mode Edit), isi otomatis kotak teks dan saklarnya
    if (widget.existingData != null) {
      _etIsiDoa.text = widget.existingData!['isiDoa'] ?? "";
      _isPrivat = widget.existingData!['isPrivat'] ?? false;
    }
  }

  @override
  void dispose() {
    _etIsiDoa.dispose();
    super.dispose();
  }

  // 👇 FUNGSI KIRIM NOTIFIKASI DOA BARU KE SEMUA JEMAAT DENGAN TIKET 👇
  Future<void> _kirimNotifDoaBaru(String namaPemohon, String churchId, bool isPrivat) async {
    final String osRestKey = osRestKeySecret; 
    final String osAppId = "a9ff250a-56ef-413d-b825-67288008d614";
    
    if (osRestKey.isEmpty) return;

    try {
      // Kalau privat, pesannya dibedakan sedikit biar admin tahu
      String pesanNotif = isPrivat 
          ? "$namaPemohon mengirimkan pokok doa khusus (Privat)."
          : "$namaPemohon baru saja membagikan pokok doa. Mari kita dukung dalam doa.";

      await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8', 
          'Authorization': 'Basic $osRestKey'
        },
        body: jsonEncode({
          "app_id": osAppId,
          "filters": [{"field": "tag", "key": "active_church", "relation": "=", "value": churchId}],
          "headings": {"en": "🙏 Permohonan Doa Baru"},
          "contents": {"en": pesanNotif},
          // 👇 INI DIA TIKET MENUJU HALAMAN DOA 👇
          "data": {
            "type": "doa"
          }
        }),
      );
    } catch (e) {
      debugPrint("Gagal kirim notif doa baru: $e");
    }
  }

  Future<void> _simpanDoa() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);

    String userUid = _auth.currentUser?.uid ?? "";
    String userNama = _userManager.userNama ?? "Jemaat";
    String? churchId = _userManager.getChurchIdForCurrentView();

    if (churchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Data gereja tidak ditemukan.")));
      setState(() => _isLoading = false);
      return;
    }

    try {
      if (widget.doaId != null) {
        // MODE EDIT
        await _db.collection("prayers").doc(widget.doaId).update({
          "isiDoa": _etIsiDoa.text.trim(),
          "isPrivat": _isPrivat,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Permohonan doa diperbarui!")));
        }
      } else {
        // MODE TAMBAH BARU
        DocumentReference docRef = _db.collection("prayers").doc();
        await docRef.set({
          "id": docRef.id,
          "uid": userUid,
          "nama": userNama, 
          "isiDoa": _etIsiDoa.text.trim(),
          "tanggal": FieldValue.serverTimestamp(), 
          "churchId": churchId,
          "isPrivat": _isPrivat,
          "daftarAmin": [], 
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Doa berhasil dibagikan!")));
        }
        
        // 👇 PANGGIL FUNGSI NOTIFIKASI SETELAH DOA BERHASIL DISIMPAN 👇
        _kirimNotifDoaBaru(userNama, churchId, _isPrivat);
      }
      
      // Tutup halaman setelah sukses
      if (mounted) Navigator.pop(context);
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal menyimpan: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isEditMode = widget.doaId != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Background abu-abu elegan
      appBar: AppBar(
        title: Text(isEditMode ? "Edit Doa" : "Tulis Doa", style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading 
        ? const LoadingSultan(size: 80)
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // HEADER TEKS
                  Row(
                    children: [
                      Icon(Icons.volunteer_activism, color: Colors.indigo.shade300, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Bagikan pergumulan Anda agar kita bisa saling menopang dalam doa.",
                          style: TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // KOTAK INPUT DOA
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]
                    ),
                    child: TextFormField(
                      controller: _etIsiDoa,
                      maxLines: 10, // Dibuat lega biar puas ngetik
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: "Ketik permohonan doa di sini...",
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.all(20),
                      ),
                      validator: (value) => value == null || value.trim().isEmpty ? "Isi doa tidak boleh kosong!" : null,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 👇 SAKLAR DOA PRIVAT SULTAN 👇
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isPrivat ? Colors.red.shade50 : Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: _isPrivat ? Colors.red.shade100 : Colors.indigo.shade100)
                    ),
                    child: SwitchListTile(
                      value: _isPrivat,
                      activeColor: Colors.red,
                      title: Text(
                        "Jadikan Privat", 
                        style: TextStyle(fontWeight: FontWeight.bold, color: _isPrivat ? Colors.red.shade700 : Colors.indigo.shade900)
                      ),
                      subtitle: Text(
                        _isPrivat ? "Hanya Anda dan Gembala/Admin yang bisa melihat doa ini." : "Semua jemaat dapat melihat dan mendoakan.",
                        style: TextStyle(fontSize: 12, color: _isPrivat ? Colors.red.shade400 : Colors.indigo.shade400),
                      ),
                      onChanged: (value) => setState(() => _isPrivat = value),
                      secondary: Icon(
                        _isPrivat ? Icons.lock : Icons.public, 
                        color: _isPrivat ? Colors.red : Colors.indigo
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // TOMBOL KIRIM
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _simpanDoa,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 4,
                      ),
                      child: Text(
                        isEditMode ? "UPDATE PERMOHONAN" : "KIRIM PERMOHONAN", 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
    );
  }
}