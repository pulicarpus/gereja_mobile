import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'anggota_keluarga_page.dart';
import 'jemaat_photo_page.dart';
import 'package:flutter/material.dart';
import 'app_safety.dart';
import 'package:cached_network_image/cached_network_image.dart';

class DetailJemaatPage extends StatelessWidget {
  final Map<String, dynamic> jemaatData;

  final bool showBirthdayGreeting;

  const DetailJemaatPage({super.key, required this.jemaatData, this.showBirthdayGreeting = false});

  @override
  Widget build(BuildContext context) {
    String nama = legacyText(jemaatData['namaLengkap'], 'Tanpa Nama');
    final rawFoto = jemaatData['fotoProfil']?.toString().trim() ?? '';
    String? fotoUrl = rawFoto.isEmpty ? null : rawFoto;
    String noHp = (jemaatData['nomorTelepon'] ?? jemaatData['noHp'] ?? "-").toString();
    String alamat = legacyText(jemaatData['alamat'], '-');
    String status = legacyText(jemaatData['statusKeluarga'], '-');
    String kategorial = (jemaatData['kelompok'] ?? jemaatData['kategorial'] ?? "Umum").toString();

    final rawBirth = jemaatData['tanggalLahir'];
    final birthDate = rawBirth is Timestamp ? rawBirth.toDate() : rawBirth is DateTime ? rawBirth : null;
    final birthText = birthDate == null ? legacyText(rawBirth, '-') : DateFormat('dd-MM-yyyy').format(birthDate);
    final familyId = legacyText(jemaatData['idKepalaKeluarga']).trim();
    final hasPhone = noHp.trim().isNotEmpty && noHp.trim() != '-';

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
            GestureDetector(
              onTap: fotoUrl == null ? null : () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => FullScreenImagePage(imageUrl: fotoUrl, heroTag: 'foto_${jemaatData['id']}'),
              )),
              child: CircleAvatar(
              radius: 60,
              backgroundColor: Colors.indigo.shade50,
              child: fotoUrl == null
                  ? const Icon(Icons.person, size: 60, color: Colors.indigo)
                  : ClipOval(child: CachedNetworkImage(
                      imageUrl: fotoUrl, width: 120, height: 120, fit: BoxFit.cover,
                      placeholder: (context, imageUrl) => const Icon(Icons.person, size: 60, color: Colors.indigo),
                      errorWidget: (context, imageUrl, error) => const Icon(Icons.person, size: 60, color: Colors.indigo),
                    )),
            ),
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
            _buildInfoRow(Icons.wc, "Jenis Kelamin", legacyText(jemaatData['jenisKelamin'], '-')),
            _buildInfoRow(Icons.water_drop, "Status Baptis", legacyText(jemaatData['statusBaptis'], 'Belum')),
            _buildInfoRow(Icons.phone, "Nomor Telepon", noHp),
            _buildInfoRow(Icons.location_on, "Alamat", alamat),
            _buildInfoRow(Icons.category, "Kategorial", kategorial),
            _buildInfoRow(Icons.cake, "Tanggal Lahir", birthText),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.people_alt_rounded),
              label: const Text('Lihat Anggota Keluarga'),
              onPressed: () {
                if (familyId.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data Keluarga tidak ditemukan')));
                  return;
                }
                Navigator.push(context, MaterialPageRoute(builder: (_) => AnggotaKeluargaPage(
                  idKepalaKeluarga: familyId, namaKepalaKeluarga: nama,
                )));
              },
            ),
            if (hasPhone) OutlinedButton.icon(
              icon: const Icon(Icons.call), label: const Text('Hubungi Jemaat'),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: noHp.trim())),
            ),
            if (hasPhone && showBirthdayGreeting) OutlinedButton.icon(
              icon: const Icon(Icons.cake), label: const Text('Ucapkan Selamat Ulang Tahun'),
              onPressed: () {
                final clean = noHp.replaceAll(RegExp(r'[^0-9+]'), '');
                final number = clean.startsWith('0') ? '62${clean.substring(1)}' : clean.replaceFirst('+', '');
                return launchUrl(Uri.https('wa.me', '/$number', {
                  'text': 'Selamat ulang tahun, $nama! Tuhan Yesus memberkati.',
                }), mode: LaunchMode.externalApplication);
              },
            ),
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
