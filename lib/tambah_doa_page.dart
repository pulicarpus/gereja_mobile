import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'user_manager.dart';
import 'secrets.dart';
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
    final existing = widget.existingData;
    if (existing != null) {
      _etIsiDoa.text = (existing['isiDoa'] ?? "").toString();
      _isPrivat = existing['isPrivat'] == true;
    }
  }

  @override
  void dispose() {
    _etIsiDoa.dispose();
    super.dispose();
  }

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<bool> _kirimNotifDoaBaru(
    String namaPemohon,
    String churchId,
    bool isPrivat,
  ) async {
    // Doa privat tidak boleh mengumumkan identitas pemohon ke seluruh gereja.
    if (isPrivat) return true;

    final osRestKey = osRestKeySecret;
    const osAppId = "a9ff250a-56ef-413d-b825-67288008d614";
    if (osRestKey.isEmpty) return false;

    try {
      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic $osRestKey',
        },
        body: jsonEncode({
          "app_id": osAppId,
          "filters": [
            {
              "field": "tag",
              "key": "active_church",
              "relation": "=",
              "value": churchId,
            }
          ],
          "headings": {"en": "🙏 Permohonan Doa Baru"},
          "contents": {
            "en": "$namaPemohon baru saja membagikan pokok doa. Mari kita dukung dalam doa."
          },
          "data": {"type": "doa"},
        }),
      );
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      if (!ok) {
        debugPrint("Notifikasi doa ditolak: ${response.statusCode}");
      }
      return ok;
    } catch (e) {
      debugPrint("Gagal kirim notif doa baru: $e");
      return false;
    }
  }

  Future<void> _simpanDoa() async {
    if (_isLoading || !(_formKey.currentState?.validate() ?? false)) return;

    final user = _auth.currentUser;
    final churchId = _userManager.getChurchIdForCurrentView();
    if (user == null) {
      _showSnack("Sesi login tidak valid. Silakan login kembali.", color: Colors.red);
      return;
    }
    if (churchId == null || churchId.trim().isEmpty) {
      _showSnack("Data gereja tidak ditemukan.", color: Colors.red);
      return;
    }

    final isEdit = widget.doaId != null;
    if (isEdit) {
      final existing = widget.existingData;
      final ownerUid = existing?['uid']?.toString() ?? "";
      final existingChurch = existing?['churchId']?.toString() ?? churchId;
      if (ownerUid != user.uid || existingChurch != churchId) {
        _showSnack("Anda tidak memiliki izin untuk mengedit doa ini.", color: Colors.red);
        return;
      }
    }

    setState(() => _isLoading = true);

    final userNamaRaw = (_userManager.userNama ?? user.displayName ?? "Jemaat").trim();
    final userNama = userNamaRaw.isEmpty ? "Jemaat" : userNamaRaw;
    final isiDoa = _etIsiDoa.text.trim();

    try {
      if (isEdit) {
        await _db.collection("prayers").doc(widget.doaId).update({
          "isiDoa": isiDoa,
          "isPrivat": _isPrivat,
        });
        _showSnack("Permohonan doa diperbarui.");
      } else {
        final docRef = _db.collection("prayers").doc();
        await docRef.set({
          "id": docRef.id,
          "uid": user.uid,
          "nama": userNama,
          "isiDoa": isiDoa,
          "tanggal": FieldValue.serverTimestamp(),
          "churchId": churchId,
          "isPrivat": _isPrivat,
          "daftarAmin": [],
        });

        final notifOk = await _kirimNotifDoaBaru(
          userNama,
          churchId,
          _isPrivat,
        );

        if (_isPrivat) {
          _showSnack("Doa privat berhasil disimpan tanpa notifikasi publik.");
        } else if (notifOk) {
          _showSnack("Doa berhasil dibagikan dan notifikasi dikirim.");
        } else {
          _showSnack(
            "Doa berhasil disimpan, tetapi notifikasi gagal dikirim.",
            color: Colors.orange,
          );
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showSnack("Gagal menyimpan permohonan doa.", color: Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.doaId != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          isEditMode ? "Edit Doa" : "Tulis Doa",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? LoadingSultan(size: 80)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.volunteer_activism,
                          color: Colors.indigo.shade300,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            "Bagikan pergumulan Anda agar kita bisa saling menopang dalam doa.",
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: TextFormField(
                        controller: _etIsiDoa,
                        maxLines: 10,
                        maxLength: 1500,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: "Ketik permohonan doa di sini...",
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(20),
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) return "Isi doa tidak boleh kosong!";
                          if (text.length > 1500) return "Isi doa terlalu panjang.";
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _isPrivat
                            ? Colors.red.shade50
                            : Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: _isPrivat
                              ? Colors.red.shade100
                              : Colors.indigo.shade100,
                        ),
                      ),
                      child: SwitchListTile(
                        value: _isPrivat,
                        activeColor: Colors.red,
                        title: Text(
                          "Jadikan Privat",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _isPrivat
                                ? Colors.red.shade700
                                : Colors.indigo.shade900,
                          ),
                        ),
                        subtitle: Text(
                          _isPrivat
                              ? "Disembunyikan dari jemaat lain di aplikasi dan tidak mengirim notifikasi publik."
                              : "Semua jemaat di gereja ini dapat melihat dan mendoakan.",
                          style: TextStyle(
                            fontSize: 12,
                            color: _isPrivat
                                ? Colors.red.shade500
                                : Colors.indigo.shade500,
                          ),
                        ),
                        onChanged: (value) =>
                            setState(() => _isPrivat = value),
                        secondary: Icon(
                          _isPrivat ? Icons.lock : Icons.public,
                          color: _isPrivat ? Colors.red : Colors.indigo,
                        ),
                      ),
                    ),
                    if (_isPrivat) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.security, size: 18, color: Colors.orange),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Privasi penuh memerlukan Firestore Rules khusus. Sampai aturan server diperketat, hindari menulis informasi yang sangat sensitif.",
                                style: TextStyle(fontSize: 12, height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _simpanDoa,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          elevation: 4,
                        ),
                        child: Text(
                          isEditMode
                              ? "UPDATE PERMOHONAN"
                              : "KIRIM PERMOHONAN",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
