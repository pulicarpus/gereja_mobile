import 'package:flutter/material.dart';

import 'chatroom_page.dart';
import 'data_jemaat_page.dart';
import 'gallery_page.dart';
import 'jadwal_page.dart';
import 'kategorial_config.dart';
import 'keuangan_page.dart';
import 'user_manager.dart';

class SubKategorialPage extends StatelessWidget {
  final String namaKomisi;

  const SubKategorialPage({
    super.key,
    required this.namaKomisi,
  });

  @override
  Widget build(BuildContext context) {
    final canonical = KategorialConfig.canonicalPelayanan(namaKomisi);
    if (canonical == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Kategorial"),
          backgroundColor: const Color(0xFF075E54),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text("Kategorial tidak dikenali.")),
      );
    }

    final user = UserManager();
    final isAdmin = user.isAdmin();
    final isMember = isAdmin ||
        KategorialConfig.same(user.userKomisi, canonical);
    final canManage = isAdmin ||
        (user.isPengurus &&
            KategorialConfig.same(user.userKomisi, canonical));

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("Pelayanan $canonical"),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor:
                        const Color(0xFF075E54).withOpacity(0.1),
                    child: const Icon(
                      Icons.account_balance,
                      size: 35,
                      color: Color(0xFF075E54),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    "Pusat Informasi $canonical",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    canManage
                        ? "Lihat anggota serta kelola chat, kegiatan, keuangan, dan galeri sesuai hak pengurus."
                        : "Lihat data anggota, kegiatan, keuangan, dan galeri pelayanan $canonical.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                  if (isMember) ...[
                    const SizedBox(height: 10),
                    _accessBadge(
                      canManage ? "ANGGOTA • PENGURUS" : "ANGGOTA",
                      const Color(0xFF075E54),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 25),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1.05,
              children: [
                _buildMenuCard(
                  context,
                  "Data Anggota",
                  Icons.people_alt_rounded,
                  Colors.blue,
                  status: "LIHAT",
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DataJemaatPage(
                        filterKategorial: canonical,
                      ),
                    ),
                  ),
                ),
                _buildMenuCard(
                  context,
                  "Chat Group",
                  Icons.chat_bubble_rounded,
                  Colors.green,
                  status: isMember ? "BUKA" : "KHUSUS ANGGOTA",
                  locked: !isMember,
                  onTap: () {
                    if (!isMember) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "Chat Group ini khusus anggota $canonical.",
                          ),
                          backgroundColor: Colors.redAccent,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatroomPage(
                          filterKategorial: canonical,
                        ),
                      ),
                    );
                  },
                ),
                _buildMenuCard(
                  context,
                  "Kegiatan",
                  Icons.event_available_rounded,
                  Colors.orange,
                  status: canManage ? "KELOLA" : "LIHAT",
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => JadwalPage(
                        filterKategorial: canonical,
                      ),
                    ),
                  ),
                ),
                _buildMenuCard(
                  context,
                  "Keuangan",
                  Icons.account_balance_wallet_rounded,
                  Colors.redAccent,
                  status: canManage ? "KELOLA" : "LIHAT",
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => KeuanganPage(
                        filterKategorial: canonical,
                      ),
                    ),
                  ),
                ),
                _buildMenuCard(
                  context,
                  "Galeri Foto",
                  Icons.photo_library_rounded,
                  Colors.purple,
                  status: canManage ? "KELOLA" : "LIHAT",
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GalleryPage(
                        filterKategorial: canonical,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _accessBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context,
    String label,
    IconData icon,
    Color color, {
    required String status,
    required VoidCallback onTap,
    bool locked = false,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        splashColor: color.withOpacity(0.1),
        highlightColor: color.withOpacity(0.05),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 32, color: color),
                  ),
                  if (locked)
                    const Positioned(
                      right: -4,
                      bottom: -2,
                      child: CircleAvatar(
                        radius: 9,
                        backgroundColor: Colors.white,
                        child: Icon(
                          Icons.lock,
                          size: 13,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: locked ? Colors.redAccent : Colors.grey.shade600,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
