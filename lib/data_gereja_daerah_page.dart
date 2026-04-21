import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart'; // 👈 Tambahan untuk buka Sosmed

import 'detail_gereja_page.dart'; 

class DataGerejaDaerahPage extends StatelessWidget {
  final String namaDaerah; 

  const DataGerejaDaerahPage({super.key, required this.namaDaerah});

  // 👇 FUNGSI UNTUK MEMBUKA LINK SOSMED 👇
  void _bukaLink(BuildContext context, String urlString, bool isWhatsApp) async {
    if (urlString.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link belum ditambahkan.")));
      return;
    }
    Uri uri;
    if (isWhatsApp) {
      String cleanNumber = urlString.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanNumber.startsWith('0')) cleanNumber = '62${cleanNumber.substring(1)}';
      uri = Uri.parse("https://wa.me/$cleanNumber");
    } else {
      if (!urlString.startsWith("http://") && !urlString.startsWith("https://")) {
        uri = Uri.parse("https://$urlString");
      } else {
        uri = Uri.parse(urlString);
      }
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tidak dapat membuka tautan.")));
    }
  }

  // 👇 FUNGSI MEMUNCULKAN POP-UP PROFIL GEMBALA 👇
  void _showProfilGembala(BuildContext context, Map<String, dynamic> data, String namaGereja) {
    String namaGembala = data['namaGembala'] ?? "Belum ada data Gembala";
    String? fotoGembala = data['fotoGembalaUrl'];
    String wa = data['waGembala'] ?? "";
    String fb = data['fbGembala'] ?? "";
    String ig = data['igGembala'] ?? "";
    String tiktok = data['tiktokGembala'] ?? "";
    String yt = data['ytGembala'] ?? "";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(25),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 25),
              
              CircleAvatar(
                radius: 50,
                backgroundColor: Colors.indigo.shade50,
                backgroundImage: fotoGembala != null ? CachedNetworkImageProvider(fotoGembala) : null,
                child: fotoGembala == null ? const Icon(Icons.person, size: 50, color: Colors.indigo) : null,
              ),
              const SizedBox(height: 15),
              
              Text(namaGembala, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87), textAlign: TextAlign.center),
              Text("Gembala Sidang $namaGereja", style: const TextStyle(fontSize: 14, color: Colors.grey)),
              
              const SizedBox(height: 25),
              const Divider(),
              const SizedBox(height: 10),
              
              const Text("Hubungi Gembala:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
              const SizedBox(height: 15),
              
              // Deretan Tombol Sosmed
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSosmedIcon(Icons.phone, Colors.green, wa.isNotEmpty, () => _bukaLink(context, wa, true)),
                  _buildSosmedIcon(Icons.facebook, Colors.blue, fb.isNotEmpty, () => _bukaLink(context, fb, false)),
                  _buildSosmedIcon(Icons.camera_alt, Colors.purple, ig.isNotEmpty, () => _bukaLink(context, ig, false)),
                  _buildSosmedIcon(Icons.music_note, Colors.black, tiktok.isNotEmpty, () => _bukaLink(context, tiktok, false)),
                  _buildSosmedIcon(Icons.play_circle_fill, Colors.red, yt.isNotEmpty, () => _bukaLink(context, yt, false)),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        );
      }
    );
  }

  Widget _buildSosmedIcon(IconData icon, Color color, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: isActive ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: isActive ? color.withOpacity(0.1) : Colors.grey.shade100, shape: BoxShape.circle),
        child: Icon(icon, color: isActive ? color : Colors.grey.shade400, size: 28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text("Gereja di $namaDaerah", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('churches')
            .where('daerah', isEqualTo: namaDaerah == "Belum Diatur" ? null : namaDaerah)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          var docs = snapshot.data?.docs ?? [];

          if (namaDaerah == "Belum Diatur") {
             docs = docs.where((doc) {
                var d = doc.data() as Map<String, dynamic>;
                return !d.containsKey('daerah') || d['daerah'] == null || d['daerah'].toString().trim().isEmpty;
             }).toList();
          }

          if (docs.isEmpty) {
             return const Center(child: Text("Tidak ada gereja di daerah ini."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var doc = docs[index];
              var docId = doc.id; 
              var data = doc.data() as Map<String, dynamic>;
              
              String namaGereja = data['namaGereja'] ?? data['churchName'] ?? "Gereja Tanpa Nama"; 
              String namaGembala = data['namaGembala'] ?? "Belum ada data Gembala";
              String alamat = data['alamat'] ?? "Alamat belum diatur";
              String? fotoGembala = data['fotoGembalaUrl'];

              return Container(
                margin: const EdgeInsets.only(bottom: 15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(15),
                  leading: CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.indigo.shade50,
                    backgroundImage: fotoGembala != null ? CachedNetworkImageProvider(fotoGembala) : null,
                    child: fotoGembala == null ? const Icon(Icons.person, color: Colors.indigo) : null,
                  ),
                  title: Text(
                    namaGereja.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 14, color: Colors.indigo),
                          const SizedBox(width: 5),
                          Expanded(child: Text("Pdt/Ev: $namaGembala", style: const TextStyle(fontSize: 13))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.location_on_outlined, size: 14, color: Colors.redAccent),
                          ),
                          const SizedBox(width: 5),
                          Expanded(child: Text(alamat, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 2, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ],
                  ),
                  // 👇 TOMBOL STATISTIK DIPINDAH KHUSUS KE IKON KANAN 👇
                  trailing: GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (context) => DetailGerejaPage(churchId: docId, namaGereja: namaGereja)
                      ));
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.analytics_outlined, color: Colors.indigo),
                    ),
                  ),
                  // 👇 KLIK BODY KARTU UNTUK LIHAT PROFIL GEMBALA 👇
                  onTap: () => _showProfilGembala(context, data, namaGereja),
                ),
              );
            },
          );
        },
      ),
    );
  }
}