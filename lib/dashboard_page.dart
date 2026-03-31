import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class DashboardPage extends StatelessWidget {
  final List<Map<String, dynamic>> allJemaat;

  const DashboardPage({super.key, required this.allJemaat});

  @override
  Widget build(BuildContext context) {
    // --- LOGIKA HITUNG DATA ---
    Map<String, int> statsKelompok = {};
    int pria = 0, wanita = 0;
    int sudahBaptis = 0, belumBaptis = 0;
    Set<String> totalKeluarga = {};

    for (var j in allJemaat) {
      // Pastikan label kelompok tidak kosong
      String k = j['kelompok'] ?? "Lainnya";
      if (k.isEmpty) k = "Lainnya";
      statsKelompok[k] = (statsKelompok[k] ?? 0) + 1;
      
      if (j['jenisKelamin'] == "Pria") pria++; else wanita++;
      if (j['statusBaptis'] == "Sudah") sudahBaptis++; else belumBaptis++;
      
      if (j['idKepalaKeluarga'] != null && j['idKepalaKeluarga'] != "") {
        totalKeluarga.add(j['idKepalaKeluarga']);
      }
    }

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
            // --- RINGKASAN ATAS ---
            Row(
              children: [
                _buildSummaryCard("Total Jemaat", "${allJemaat.length}", Icons.people, Colors.indigo),
                const SizedBox(width: 15),
                _buildSummaryCard("Total Keluarga", "${totalKeluarga.length}", Icons.family_restroom, Colors.green),
              ],
            ),
            const SizedBox(height: 30),

            // --- GRAFIK KELOMPOK (BAR LEBIH BESAR & LABEL JELAS) ---
            const Text("Kelompok Kategorial", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: statsKelompok.entries.toList().asMap().entries.map((e) {
                    double progress = e.value.value / (allJemaat.isEmpty ? 1 : allJemaat.length);
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
                              minHeight: 25, // BAR DIPERBESAR / DIPERTEBAL
                              backgroundColor: Colors.grey[200],
                              color: colors[e.key % colors.length],
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

            // --- GRAFIK PIE (GENDER & BAPTIS DENGAN LABEL JELAS) ---
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

  Widget _buildSummaryCard(String title, String val, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 35),
            const SizedBox(height: 10),
            Text(val, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ],
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
                    centerSpaceRadius: 0, // Dibuat penuh tanpa lubang biar teks muat
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