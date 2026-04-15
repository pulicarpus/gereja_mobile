import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'user_manager.dart';

class DetailSeksiPage extends StatelessWidget {
  final String docId;
  final String namaSeksi;

  const DetailSeksiPage({super.key, required this.docId, required this.namaSeksi});

  void _bukaWA(BuildContext context, String wa) async {
    if (wa.isEmpty) return;
    String cleanWa = wa.replaceAll(RegExp(r'[-\s+]'), '');
    if (cleanWa.startsWith('0')) cleanWa = '62${cleanWa.substring(1)}';
    final Uri url = Uri.parse("https://wa.me/$cleanWa");
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final UserManager userManager = UserManager();
    final String churchId = userManager.getChurchIdForCurrentView()!;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text("Struktur $namaSeksi", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection("churches").doc(churchId).collection("bpj_seksi").doc(docId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. PENGURUS INTI SEKSI (KETUA, SEK, BEN)
              const Text("PENGURUS HARIAN", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 10),
              
              _buildPersonTile(context, "KETUA", data['ketua_nama'] ?? data['namaPengurus'] ?? "", data['ketua_wa'] ?? data['telepon'] ?? "", data['ketua_img'] ?? data['fotoUrl']),
              
              // 👇 LOGIKA GAIB: HANYA TAMPIL JIKA NAMA TIDAK KOSONG 👇
              if (data['sek_nama'] != null && data['sek_nama'] != "")
                _buildPersonTile(context, "SEKRETARIS", data['sek_nama'], data['sek_wa'], data['sek_img']),
                
              if (data['bend_nama'] != null && data['bend_nama'] != "")
                _buildPersonTile(context, "BENDAHARA", data['bend_nama'], data['bend_wa'], data['bend_img']),

              const SizedBox(height: 25),

              // 2. DAFTAR ANGGOTA
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("ANGGOTA", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                  if (userManager.isAdmin())
                    TextButton.icon(
                      onPressed: () => _showAddAnggotaDialog(context, churchId, data['anggota'] ?? []),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text("Tambah"),
                    )
                ],
              ),
              const SizedBox(height: 10),
              
              _buildAnggotaList(context, churchId, data['anggota'] ?? []),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPersonTile(BuildContext context, String jabatan, String nama, String wa, String? img) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.indigo.shade50,
          backgroundImage: img != null && img != "" ? CachedNetworkImageProvider(img) : null,
          child: img == null || img == "" ? const Icon(Icons.person, color: Colors.indigo) : null,
        ),
        title: Text(nama, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(jabatan, style: const TextStyle(fontSize: 12, color: Colors.indigo)),
        trailing: wa != "" ? IconButton(icon: const Icon(Icons.chat, color: Colors.green), onPressed: () => _bukaWA(context, wa)) : null,
      ),
    );
  }

  Widget _buildAnggotaList(BuildContext context, String churchId, List<dynamic> anggota) {
    if (anggota.isEmpty) return const Center(child: Text("Belum ada anggota.", style: TextStyle(color: Colors.grey, fontSize: 13)));
    
    return Column(
      children: anggota.map((nama) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.person_outline, size: 20, color: Colors.grey),
          title: Text(nama.toString(), style: const TextStyle(fontWeight: FontWeight.w500)),
          trailing: UserManager().isAdmin() ? IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            onPressed: () => _removeAnggota(churchId, anggota, nama.toString()),
          ) : null,
        ),
      )).toList(),
    );
  }

  void _showAddAnggotaDialog(BuildContext context, String churchId, List<dynamic> currentList) {
    final etName = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Tambah Anggota", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(controller: etName, decoration: const InputDecoration(hintText: "Nama Anggota")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () {
              if (etName.text.isEmpty) return;
              List<String> newList = List<String>.from(currentList);
              newList.add(etName.text.trim());
              FirebaseFirestore.instance.collection("churches").doc(churchId).collection("bpj_seksi").doc(docId).update({"anggota": newList});
              Navigator.pop(c);
            },
            child: const Text("Simpan"),
          )
        ],
      )
    );
  }

  void _removeAnggota(String churchId, List<dynamic> currentList, String target) {
    List<String> newList = List<String>.from(currentList);
    newList.remove(target);
    FirebaseFirestore.instance.collection("churches").doc(churchId).collection("bpj_seksi").doc(docId).update({"anggota": newList});
  }
}