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
      String k = j['kelompok'] ?? "Lainnya";
      statsKelompok[k] = (statsKelompok[k] ?? 0) + 1;
      
      if (j['jenisKelamin'] == "Pria") pria++; else wanita++;
      if (j['statusBaptis'] == "Sudah") sudahBaptis++; else belumBaptis++;
      
      if (j['idKepalaKeluarga'] != null && j['idKepalaKeluarga'] != "") {
        totalKeluarga.add(j['idKepalaKeluarga']);
      }
    }

    final List<Color> colors = [
      Colors.indigo, Colors.redAccent, Colors.green, 
      Colors.orange, Colors.purple, Colors.teal
    ];

    return Scaffold(
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

            // --- GRAFIK KELOMPOK (HORIZONTAL BARS) ---
            const Text("Kelompok Kategorial", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: statsKelompok.entries.toList().asMap().entries.map((e) {
                    double progress = e.value.value / (allJemaat.isEmpty ? 1 : allJemaat.length);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.value.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text("${e.value.value} Orang", style: const TextStyle(color: Colors.grey)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 15,
                              backgroundColor: Colors.grey.shade100,
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

            // --- GRAFIK PIE (GENDER & BAPTIS) ---
            Row(
              children: [
                _buildPieCard("Gender", [
                  PieChartSectionData(value: pria.toDouble(), title: '$pria', color: Colors.blue, radius: 50, titleStyle: _pieStyle),
                  PieChartSectionData(value: wanita.toDouble(), title: '$wanita', color: Colors.pink, radius: 50, titleStyle: _pieStyle),
                ], "Pria vs Wanita"),
                const SizedBox(width: 15),
                _buildPieCard("Baptisan", [
                  PieChartSectionData(value: sudahBaptis.toDouble(), title: '$sudahBaptis', color: Colors.green, radius: 50, titleStyle: _pieStyle),
                  PieChartSectionData(value: belumBaptis.toDouble(), title: '$belumBaptis', color: Colors.grey, radius: 50, titleStyle: _pieStyle),
                ], "Sudah vs Belum"),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  final _pieStyle = const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14);

  Widget _buildSummaryCard(String title, String val, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 10),
            Text(val, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildPieCard(String title, List<PieChartSectionData> sections, String footer) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              SizedBox(height: 120, child: PieChart(PieChartData(sectionsSpace: 3, centerSpaceRadius: 20, sections: sections))),
              const SizedBox(height: 10),
              Text(footer, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}