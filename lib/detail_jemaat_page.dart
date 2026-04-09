import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class DetailJemaatPage extends StatelessWidget {
  final Map<String, dynamic> jemaatData;

  const DetailJemaatPage({super.key, required this.jemaatData});

  @override
  Widget build(BuildContext context) {
    String nama = jemaatData['namaLengkap'] ?? "Tanpa Nama";
    String? fotoUrl = jemaatData['fotoProfil'];
    String noHp = jemaatData['noHp'] ?? "-";
    String alamat = jemaatData['alamat'] ?? "-";
    String status = jemaatData['statusKeluarga'] ?? "-";
    String kategorial = jemaatData['kategorial'] ?? "Umum";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Detail Jemaat"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.indigo.shade50,
              backgroundImage: fotoUrl != null ? CachedNetworkImageProvider(fotoUrl) : null,
              child: fotoUrl == null ? const Icon(Icons.person, size: 60, color: Colors.indigo) : null,
            ),
            const SizedBox(height: 20),
            Text(nama, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(15)),
              child: Text(status, style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 30),
            const Divider(),
            _buildInfoRow(Icons.phone, "Nomor HP", noHp),
            _buildInfoRow(Icons.location_on, "Alamat", alamat),
            _buildInfoRow(Icons.category, "Kategorial", kategorial),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.indigo.shade50, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.indigo),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          )
        ],
      ),
    );
  }
}