import 'package:flutter/material.dart';

import 'daerah_records_page.dart';
import 'data_gereja_daerah_page.dart';
import 'dashboard_daerah_page.dart';
import 'keuangan_daerah_page.dart';
import 'info_surat_daerah_page.dart';

class MenuDaerahPage extends StatelessWidget {
  final String namaDaerah;
  const MenuDaerahPage({super.key, required this.namaDaerah});

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FA),
    appBar: AppBar(
      title: Text(
        "Pusat Kendali - $namaDaerah",
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      backgroundColor: Colors.indigo.shade900,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.indigo.shade900, Colors.blue.shade800],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.account_balance_outlined,
                      size: 32,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            namaDaerah,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Informasi dan administrasi daerah',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final fontSize = MediaQuery.textScalerOf(context).scale(12);
                  final minimumWidth =
                      100.0 * (fontSize / 12).clamp(1, double.infinity);
                  final columns =
                      ((constraints.maxWidth + 12) / (minimumWidth + 12))
                          .floor()
                          .clamp(1, 4)
                          .toInt();
                  final height =
                      128.0 + (fontSize - 12).clamp(0, double.infinity) * 6;
                  return GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: height,
                    ),
                    children: [
                      _menu(
                        context,
                        Icons.church_outlined,
                        'Data Gereja & Pengerja',
                        Colors.blue,
                        () => _open(
                          context,
                          DataGerejaDaerahPage(namaDaerah: namaDaerah),
                        ),
                      ),
                      _menu(
                        context,
                        Icons.analytics_outlined,
                        'Dashboard Statistik',
                        Colors.purple,
                        () => _open(
                          context,
                          DashboardDaerahPage(namaDaerah: namaDaerah),
                        ),
                      ),
                      _menu(
                        context,
                        Icons.account_balance_wallet_outlined,
                        'Laporan Keuangan',
                        Colors.green,
                        () => _open(
                          context,
                          KeuanganDaerahPage(namaDaerah: namaDaerah),
                        ),
                      ),
                      _menu(
                        context,
                        Icons.badge_outlined,
                        'Pengurus Daerah',
                        Colors.orange,
                        () => _open(
                          context,
                          DaerahRecordsPage(
                            namaDaerah: namaDaerah,
                            type: DaerahRecordType.pengurus,
                          ),
                        ),
                      ),
                      _menu(
                        context,
                        Icons.inventory_2_outlined,
                        'Inventaris Daerah',
                        Colors.teal,
                        () => _open(
                          context,
                          DaerahRecordsPage(
                            namaDaerah: namaDaerah,
                            type: DaerahRecordType.inventaris,
                          ),
                        ),
                      ),
                      _menu(
                        context,
                        Icons.notifications_active_outlined,
                        'Info & Surat Daerah',
                        Colors.redAccent,
                        () => _open(
                          context,
                          InfoSuratDaerahPage(namaDaerah: namaDaerah),
                        ),
                      ),
                      _menu(
                        context,
                        Icons.settings_outlined,
                        'Pengaturan Daerah',
                        Colors.blueGrey,
                        () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Pengaturan $namaDaerah')),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _menu(
    BuildContext context,
    IconData icon,
    String title,
    Color color,
    VoidCallback onTap,
  ) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, size: 23, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
