import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'loading_sultan.dart';

class DashboardDaerahPage extends StatefulWidget {
  const DashboardDaerahPage({super.key});

  @override
  State<DashboardDaerahPage> createState() => _DashboardDaerahPageState();
}

class _DashboardDaerahPageState extends State<DashboardDaerahPage> {
  final _db = FirebaseFirestore.instance;
  bool _isLoading = true;

  // Variabel Penampung Statistik
  int totalJemaatDaerah = 0;
  int totalGereja = 0;
  int pria = 0;
  int wanita = 0;
  Map<String, int> kategorialStats = {
    "Sekolah Minggu": 0,
    "AMKI": 0,
    "Perkawan": 0,
    "Perkaria": 0,
    "Lainnya": 0,
  };

  @override
  void initState() {
    super.initState();
    _hitungDataGlobal();
  }

  // 👇 MESIN PINTAR PENGHITUNG DATA SE-DAERAH 👇
  Future<void> _hitungDataGlobal() async {
    try {
      var snapGereja = await _db.collection("churches").get();
      totalGereja = snapGereja.docs.length;

      int tempTotal = 0;
      int tempPria = 0;
      int tempWanita = 0;
      Map<String, int> tempKat = {
        "Sekolah Minggu": 0, "AMKI": 0, "Perkawan": 0, "Perkaria": 0, "Lainnya": 0,
      };

      for (var docGereja in snapGereja.docs) {
        var snapJemaat = await docGereja.reference.collection("jemaat").get();
        tempTotal += snapJemaat.docs.length;

        for (var docJemaat in snapJemaat.docs) {
          var data = docJemaat.data();
          
          // Hitung Gender
          if (data['jenisKelamin'] == "Pria") tempPria++;
          if (data['jenisKelamin'] == "Wanita") tempWanita++;

          // Hitung Kategorial
          String kat = data['kelompok'] ?? "Lainnya";
          if (tempKat.containsKey(kat)) {
            tempKat[kat] = tempKat[kat]! + 1;
          }
        }
      }

      if (mounted) {
        setState(() {
          totalJemaatDaerah = tempTotal;
          pria = tempPria;
          wanita = tempWanita;
          kategorialStats = tempKat;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error Dashboard Daerah: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Dashboard Pengurus Daerah", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const LoadingSultan(size: 80)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderStats(),
                  const SizedBox(height: 25),
                  const Text("Analisis Gender Jemaat", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  _buildGenderChart(),
                  const SizedBox(height: 30),
                  const Text("Sebaran Kategorial Daerah", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  _buildKategorialChart(),
                  const SizedBox(height: 50),
                ],
              ),
            ),
    );
  }

  // WIDGET 1: RINGKASAN ANGKA
  Widget _buildHeaderStats() {
    return Row(
      children: [
        _cardRingkasan("TOTAL JEMAAT", totalJemaatDaerah.toString(), Icons.people, Colors.blue),
        const SizedBox(width: 15),
        _cardRingkasan("TOTAL GEREJA", totalGereja.toString(), Icons.church, Colors.orange),
      ],
    );
  }

  Widget _cardRingkasan(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 15),
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // WIDGET 2: GRAFIK PIE GENDER
  Widget _buildGenderChart() {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(value: pria.toDouble(), color: Colors.blue, title: "${((pria/totalJemaatDaerah)*100).toStringAsFixed(1)}%", radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  PieChartSectionData(value: wanita.toDouble(), color: Colors.pink, title: "${((wanita/totalJemaatDaerah)*100).toStringAsFixed(1)}%", radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _indicator(Colors.blue, "Pria ($pria)"),
              const SizedBox(height: 10),
              _indicator(Colors.pink, "Wanita ($wanita)"),
            ],
          )
        ],
      ),
    );
  }

  // WIDGET 3: GRAFIK BATANG KATEGORIAL
  Widget _buildKategorialChart() {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (kategorialStats.values.reduce((a, b) => a > b ? a : b) + 10).toDouble(),
          barGroups: kategorialStats.entries.map((e) {
            int index = kategorialStats.keys.toList().indexOf(e.key);
            return BarChartGroupData(
              x: index,
              barRods: [BarChartRodData(toY: e.value.toDouble(), color: Colors.indigo, width: 15, borderRadius: BorderRadius.circular(4))],
            );
          }).toList(),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  return Text(kategorialStats.keys.toList()[value.toInt()].substring(0, 3), style: const TextStyle(fontSize: 10));
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _indicator(Color color, String text) {
    return Row(children: [Container(width: 12, height: 12, color: color), const SizedBox(width: 8), Text(text)]);
  }
}