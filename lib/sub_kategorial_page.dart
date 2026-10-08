import 'package:flutter/material.dart';

import 'chatroom_page.dart';
import 'data_jemaat_page.dart';
import 'gallery_page.dart';
import 'jadwal_page.dart';
import 'kategorial_config.dart';
import 'kategorial_menu_widgets.dart';
import 'keuangan_page.dart';
import 'user_manager.dart';

class SubKategorialPage extends StatelessWidget {
  final String namaKomisi;

  const SubKategorialPage({super.key, required this.namaKomisi});

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
    final isMember =
        isAdmin || KategorialConfig.same(user.userKomisi, canonical);
    final canManage =
        isAdmin ||
        (user.isPengurus && KategorialConfig.same(user.userKomisi, canonical));

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("Pelayanan $canonical"),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF075E54).withOpacity(0.1),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: Color(0xFF075E54),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            canonical,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            canManage
                                ? "Informasi dan pengelolaan pelayanan Anda."
                                : "Anggota, kegiatan, dan informasi pelayanan.",
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  height: 1.5,
                                ),
                          ),
                          if (isMember) ...[
                            const SizedBox(height: 12),
                            _accessBadge(
                              canManage ? "Anggota • Pengurus" : "Anggota",
                              const Color(0xFF075E54),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                KategorialMenuSection(
                  children: [
                    _buildMenuRow(
                      context,
                      "Data Anggota",
                      Icons.people_alt_rounded,
                      Colors.blue,
                      status: "LIHAT",
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              DataJemaatPage(filterKategorial: canonical),
                        ),
                      ),
                    ),
                    _buildMenuRow(
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
                            builder: (_) =>
                                ChatroomPage(filterKategorial: canonical),
                          ),
                        );
                      },
                    ),
                    _buildMenuRow(
                      context,
                      "Kegiatan",
                      Icons.event_available_rounded,
                      Colors.orange,
                      status: canManage ? "KELOLA" : "LIHAT",
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              JadwalPage(filterKategorial: canonical),
                        ),
                      ),
                    ),
                    _buildMenuRow(
                      context,
                      "Keuangan",
                      Icons.account_balance_wallet_rounded,
                      Colors.redAccent,
                      status: canManage ? "KELOLA" : "LIHAT",
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              KeuanganPage(filterKategorial: canonical),
                        ),
                      ),
                    ),
                    _buildMenuRow(
                      context,
                      "Galeri Foto",
                      Icons.photo_library_rounded,
                      Colors.purple,
                      status: canManage ? "KELOLA" : "LIHAT",
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              GalleryPage(filterKategorial: canonical),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
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

  Widget _buildMenuRow(
    BuildContext context,
    String label,
    IconData icon,
    Color color, {
    required String status,
    required VoidCallback onTap,
    bool locked = false,
  }) {
    final description = switch (label) {
      "Data Anggota" => "Lihat anggota pelayanan",
      "Chat Group" =>
        locked ? "Khusus anggota $namaKomisi" : "Percakapan bersama anggota",
      "Kegiatan" =>
        status == "KELOLA"
            ? "Lihat dan kelola jadwal kegiatan"
            : "Jadwal dan kegiatan pelayanan",
      "Keuangan" =>
        status == "KELOLA"
            ? "Laporan dan pengelolaan keuangan"
            : "Lihat laporan keuangan",
      "Galeri Foto" =>
        status == "KELOLA"
            ? "Lihat dan kelola dokumentasi"
            : "Dokumentasi kegiatan pelayanan",
      _ => status,
    };
    return KategorialMenuRow(
      title: label,
      subtitle: description,
      icon: icon,
      color: color,
      locked: locked,
      onTap: onTap,
    );
  }
}
