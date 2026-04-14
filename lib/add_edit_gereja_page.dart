import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import 'loading_sultan.dart';

class AddEditGerejaPage extends StatefulWidget {
  final String? gerejaId;

  const AddEditGerejaPage({super.key, this.gerejaId});

  @override
  State<AddEditGerejaPage> createState() => _AddEditGerejaPageState();
}

class _AddEditGerejaPageState extends State<AddEditGerejaPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final _etNama = TextEditingController();
  final _etAlamat = TextEditingController();
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.gerejaId != null) {
      _loadGerejaData();
    }
  }

  @override
  void dispose() {
    _etNama.dispose();
    _etAlamat.dispose();
    super.dispose();
  }

  Future<void> _loadGerejaData() async {
    setState(() => _isLoading = true);
    try {
      var doc = await _db.collection("churches").doc(widget.gerejaId).get();
      if (doc.exists) {
        var data = doc.data()!;
        _etNama.text = data['nama'] ?? "";
        _etAlamat.text = data['alamat'] ?? "";
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveGereja() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);

    String nama = _etNama.text.trim();
    String alamat = _etAlamat.text.trim();

    try {
      if (widget.gerejaId != null) {
        await _db.collection("churches").doc(widget.gerejaId).update({
          "nama": nama,
          "alamat": alamat,
          "lastUpdate": FieldValue.serverTimestamp(),
        });
      } else {
        String kodeUnik = nama.replaceAll(" ", "").toUpperCase();
        if (kodeUnik.length > 5) {
          kodeUnik = kodeUnik.substring(0, 5); 
        }
        String kodeUndangan = "$kodeUnik${Random().nextInt(900) + 100}"; 

        await _db.collection("churches").add({
          "nama": nama,
          "alamat": alamat,
          "kodeUndangan": kodeUndangan,
          "createdAt": FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data gereja berhasil disimpan!")));
        Navigator.pop(context); 
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal menyimpan: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.gerejaId == null ? "Tambah Gereja" : "Edit Gereja"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const LoadingSultan(size: 80)
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    "Informasi Gereja",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                  const SizedBox(height: 20),
                  
                  TextFormField(
                    controller: _etNama,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: "Nama Gereja",
                      prefixIcon: const Icon(Icons.church),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return "Nama gereja tidak boleh kosong";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _etAlamat,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: "Alamat Lengkap",
                      prefixIcon: const Icon(Icons.location_on),
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 40),

                  ElevatedButton.icon(
                    onPressed: _saveGereja,
                    icon: const Icon(Icons.save),
                    label: const Text("SIMPAN GEREJA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo[900],
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}