import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'user_manager.dart'; // Pastikan file ini di-import

class DashboardPage extends StatefulWidget {
  final List<Map<String, dynamic>> allJemaat;
  final String? churchId;

  const DashboardPage({super.key, required this.allJemaat, this.churchId});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late List<Map<String, dynamic>> _localJemaat;
  final UserManager _userManager = UserManager(); // Inisialisasi UserManager

  @override
  void initState() {
    super.initState();
    _localJemaat = List.from(widget.allJemaat);
  }

  // Fungsi untuk menampilkan BottomSheet daftar jemaat yang meninggal
  void _showDaftarMeninggal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          final listMeninggal = _localJemaat.where((j) => j['status'] == 'Meninggal').toList();

          return Container(
            padding: const EdgeInsets.all(20),
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Daftar Jemaat Meninggal", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Text("Ketuk menu pada nama untuk membatalkan status atau menghapus permanen.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                const Divider(height: 20),
                Expanded(
                  child: listMeninggal.isEmpty
                      ? const Center(child: Text("Tidak ada data jemaat meninggal.", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: listMeninggal.length,
                          itemBuilder: (context, index) {
                            final j = listMeninggal[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: (j['fotoProfil'] != null && j['fotoProfil'] != "") ? NetworkImage(j['fotoProfil']) : null,
                                  child: (j['fotoProfil'] == null || j['fotoProfil'] == "") ? Text(j['namaLengkap']?[0] ?? "?") : null,
                                ),
                                title: Text(j['namaLengkap'] ?? "-", style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text("${j['kelompok'] ?? "-"} • ${j['statusKeluarga'] ?? ""}"),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    if (widget.churchId == null) return;

                                    if (value == 'batal') {
                                      // 1. Batalkan status meninggal (kembalikan ke aktif)
                                      await FirebaseFirestore.instance
                                          .collection("churches")
                                          .doc(widget.churchId)
                                          .collection("jemaat")
                                          .doc(j['id'])
                                          .update({'status': null});

                                      setState(() {
                                        int idx = _localJemaat.indexWhere((item) => item['id'] == j['id']);
                                        if (idx != -1) {
                                          _localJemaat[idx]['status'] = null;
                                        }
                                      });
                                      setModalState(() {});
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text("Status meninggal dibatalkan. Jemaat kembali aktif.")),
                                      );
                                    } else if (value == 'hapus') {
                                      // 2. Hapus permanen dari database
                                      await FirebaseFirestore.instance
                                          .collection("churches")
                                          .doc(widget.churchId)
                                          .collection("jemaat")
                                          .doc(j['id'])
                                          .delete();

                                      setState(() {
                                        _localJemaat.removeWhere((item) => item['id'] == j['id']);
                                      });
                                      setModalState(() {});
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text("Data berhasil dihapus permanen dari database.")),
                                      );
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'batal',
                                      child: Row(
                                        children: [
                                          Icon(Icons.restore, color: Colors.green),
                                          SizedBox(width: 8),
                                          Text("Batalkan (Jadikan Aktif)"),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'hapus',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_forever, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text("Hapus Permanen"),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // --- LOGIKA HITUNG DATA BERDASARKAN _localJemaat ---
    Map<String, int> statsKelompok = {};
    int pria = 0, wanita = 0;
    int sudahBaptis = 0, belumBaptis = 0;
    int meninggal = 0;
    int lahirTahunIni = 0;
    Set<String> totalKeluarga = {};

    String currentYear = DateTime.now().year.toString();

    for (var j in _localJemaat) {
      if (j['status'] == 'Meninggal') {
        meninggal++;
        continue;
      }

      String? tglLahir = j['tanggalLahir'];
      if (tglLahir != null && tglLahir.contains(currentYear)) {
        lahirTahunIni++;
      }

      String k = j['kelompok'] ?? "Lainnya";
      if (k.isEmpty) k = "Lainnya";
      statsKelompok[k] = (statsKelompok[k] ?? 0) + 1;
      
      if (j['jenisKelamin'] == "Pria") pria++; else wanita++;
      if (j['statusBaptis'] == "Sudah") sudahBaptis++; else belumBaptis++;
      
      if (j['idKepalaKeluarga'] != null && j['idKepalaKeluarga'] != "") {
        totalKeluarga.add(j['idKepalaKeluarga']);
      }
    }

    int totalJemaatAktif = _localJemaat.length - meninggal;

    final List<Color> colors = [
      Colors.indigo, Colors.redAccent, Colors.green, 
      Colors.orange, Colors.purple, Colors.teal, Colors.brown
    ];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Dashboard Statistik"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- RINGKASAN ATAS (BARIS 1) ---
            Row(
              children: [
                _buildSummaryCard("Jemaat Aktif", "$totalJemaatAktif", Icons.people, Colors.indigo),
                const SizedBox(width: 15),
                _buildSummaryCard("Total Keluarga", "${totalKeluarga.length}", Icons.family_restroom, Colors.green),
              ],
            ),
            const SizedBox(height: 15),

            // --- RINGKASAN TAMBAHAN (BARIS 2: LAHIR & MENINGGAL) ---
            Row(
              children: [
                _buildSummaryCard("Lahir Tahun Ini", "$lahirTahunIni", Icons.cake, Colors.teal),
                const SizedBox(width: 15),
                // KARTU MENINGGAL HANYA BISA DIKLIK OLEH ADMIN/SUPERADMIN
                _buildSummaryCard(
                  "Meninggal", 
                  "$meninggal", 
                  Icons.heart_broken_rounded, 
                  Colors.grey[700]!, 
                  onTap: _userManager.isAdmin() ? () => _showDaftarMeninggal(context) : null,
                ),
              ],
            ),
            const SizedBox(height: 30),

            // --- GRAFIK KELOMPOK ---
            const Text("Kelompok Kategorial", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: statsKelompok.entries.toList().asMap().entries.map((e) {
                    double progress = e.value.value / (totalJemaatAktif == 0 ? 1 : totalJemaatAktif);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.value.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              Text("${e.value.value} Jiwa", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 25,
                              backgroundColor: Colors.grey[200],
                              color: colors[e.key.hashCode % colors.length],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 30),

            // --- GRAFIK PIE ---
            const Text("Distribusi Data", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Row(
              children: [
                _buildPieCard("Gender", [
                  PieChartSectionData(value: pria.toDouble(), title: 'Pria\n$pria', color: Colors.blue[600]!, radius: 60, titleStyle: _pieStyle),
                  PieChartSectionData(value: wanita.toDouble(), title: 'Wnt\n$wanita', color: Colors.pink[400]!, radius: 60, titleStyle: _pieStyle),
                ]),
                const SizedBox(width: 15),
                _buildPieCard("Baptisan", [
                  PieChartSectionData(value: sudahBaptis.toDouble(), title: 'Sdh\n$sudahBaptis', color: Colors.green[600]!, radius: 60, titleStyle: _pieStyle),
                  PieChartSectionData(value: belumBaptis.toDouble(), title: 'Blm\n$belumBaptis', color: Colors.orange[700]!, radius: 60, titleStyle: _pieStyle),
                ]),
              ],
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  final _pieStyle = const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13);

  Widget _buildSummaryCard(String title, String val, IconData icon, Color color, {VoidCallback? onTap}) {
    return Expanded(
      child: Material(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap, // onTap bisa null jika bukan admin
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: color.withOpacity(0.3), width: 2),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 30),
                const SizedBox(height: 8),
                Text(val, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 4),
                Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPieCard(String title, List<PieChartSectionData> sections) {
    return Expanded(
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
          child: Column(
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 20),
              SizedBox(
                height: 140, 
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 4, 
                    centerSpaceRadius: 0, 
                    sections: sections
                  )
                )
              ),
            ],
          ),
        ),
      ),
    );
  }
}