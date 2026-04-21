import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'loading_sultan.dart';

class DashboardDaerahPage extends StatefulWidget {
  final String? namaDaerah; // 👈 SEKARANG MENERIMA NAMA DAERAH

  const DashboardDaerahPage({super.key, this.namaDaerah});

  @override
  State<DashboardDaerahPage> createState() => _DashboardDaerahPageState();
}

class _DashboardDaerahPageState extends State<DashboardDaerahPage> {
  final _db = FirebaseFirestore.instance;
  bool _isLoading = true;

  // Variabel Penampung Statistik Jemaat & Gereja
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

  // 👇 VARIABEL BARU UNTUK PENGERJA 👇
  int totalPengerja = 0;
  int totalPdt = 0;
  int totalVic = 0;
  int totalEv = 0;

  @override
  void initState() {
    super.initState();
    _hitungDataGlobal();
  }

  // 👇 MESIN PINTAR PENGHITUNG DATA SE-DAERAH 👇
  Future<void> _hitungDataGlobal() async {
    try {
      // 1. Ambil gereja sesuai daerah yang dipilih
      Query churchQuery = _db.collection("churches");
      if (widget.namaDaerah != null && widget.namaDaerah != "Belum Diatur") {
        churchQuery = churchQuery.where('daerah', isEqualTo: widget.namaDaerah);
      }
      var snapGereja = await churchQuery.get();
      
      List<QueryDocumentSnapshot> docs = snapGereja.docs;

      // Filter manual jika daerah "Belum Diatur"
      if (widget.namaDaerah == "Belum Diatur") {
        docs = docs.where((doc) {
          var d = doc.data() as Map<String, dynamic>;
          return !d.containsKey('daerah') || d['daerah'] == null || d['daerah'].toString().trim().isEmpty;
        }).toList();
      }

      totalGereja = docs.length;

      int tempTotal = 0, tempPria = 0, tempWanita = 0;
      int tempPengerja = 0, tempPdt = 0, tempVic = 0, tempEv = 0;
      Map<String, int> tempKat = {
        "Sekolah Minggu": 0, "AMKI": 0, "Perkawan": 0, "Perkaria": 0, "Lainnya": 0,
      };

      for (var docGereja in docs) {
        var dataGereja = docGereja.data() as Map<String, dynamic>;
        
        // 👇 DETEKTOR GELAR PENGERJA DARI NAMA GEMBALA 👇
        String gembala = (dataGereja['namaGembala'] ?? "").toString().toLowerCase();
        bool isPengerja = false;

        if (gembala.contains("pdt") || gembala.contains("pendeta")) {
          tempPdt++;
          isPengerja = true;
        } else if (gembala.contains("vic") || gembala.contains("vik")) {
          tempVic++;
          isPengerja = true;
        } else if (gembala.contains("ev") || gembala.contains("penginjil")) {
          tempEv++;
          isPengerja = true;
        } else if (gembala.isNotEmpty && !gembala.contains("belum ada")) {
          // Tidak ada gelar tapi ada namanya, tetap dihitung 1 pengerja
          isPengerja = true; 
        }

        if (isPengerja) tempPengerja++;

        // 👇 HITUNG JEMAAT 👇
        var snapJemaat = await docGereja.reference.collection("jemaat").get();
        tempTotal += snapJemaat.docs.length;

        for (var docJemaat in snapJemaat.docs) {
          var data = docJemaat.data();
          
          // Hitung Gender
          String jk = (data['jenisKelamin'] ?? "").toString().toLowerCase();
          if (jk == "pria" || jk == "laki-laki" || jk == "l") tempPria++;
          if (jk == "wanita" || jk == "perempuan" || jk == "p") tempWanita++;

          // Hitung Kategorial (Membaca field 'kelompok')
          String kat = data['kelompok'] ?? "Lainnya";
          if (!tempKat.containsKey(kat)) kat = "Lainnya";
          tempKat[kat] = tempKat[kat]! + 1;
        }
      }

      if (mounted) {
        setState(() {
          totalJemaatDaerah = tempTotal;
          pria = tempPria;
          wanita = tempWanita;
          kategorialStats = tempKat;
          
          // Update Variabel Pengerja
          totalPengerja = tempPengerja;
          totalPdt = tempPdt;
          totalVic = tempVic;
          totalEv = tempEv;

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error Dashboard Daerah: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String judul = widget.namaDaerah != null ? "Statistik ${widget.namaDaerah}" : "Dashboard Daerah";

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(judul, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                  const Text("Ringkasan Umum", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  const SizedBox(height: 15),
                  _buildHeaderStats(),
                  const SizedBox(height: 30),

                  // 👇 BLOK BARU UNTUK DATA PENGERJA 👇
                  const Text("Kekuatan Hamba Tuhan", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  const SizedBox(height: 15),
                  _buildPengerjaStats(),
                  const SizedBox(height: 30),

                  const Text("Analisis Gender Jemaat", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  const SizedBox(height: 15),
                  _buildGenderChart(),
                  const SizedBox(height: 30),

                  const Text("Sebaran Kategorial Daerah", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
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
        _cardRingkasan("TOTAL\nJEMAAT", totalJemaatDaerah.toString(), Icons.people, Colors.blue),
        const SizedBox(width: 15),
        _cardRingkasan("TOTAL\nGEREJA", totalGereja.toString(), Icons.church, Colors.orange),
      ],
    );
  }

  // 👇 WIDGET BARU: KARTU PENGERJA 👇
  Widget _buildPengerjaStats() {
    return Column(
      children: [
        Row(
          children: [
            _cardRingkasan("TOTAL\nPENGERJA", totalPengerja.toString(), Icons.assignment_ind, Colors.purple),
            const SizedBox(width: 15),
            _cardRingkasan("PENDETA\n(PDT)", totalPdt.toString(), Icons.menu_book, Colors.teal),
          ],
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            _cardRingkasan("VICARIS\n(VIC)", totalVic.toString(), Icons.school, Colors.brown),
            const SizedBox(width: 15),
            _cardRingkasan("PENGINJIL\n(EV)", totalEv.toString(), Icons.record_voice_over, Colors.deepOrange),
          ],
        ),
      ],
    );
  }

  Widget _cardRingkasan(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 15),
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  // WIDGET 2: GRAFIK PIE GENDER (Sudah Anti-Crash kalau kosong)
  Widget _buildGenderChart() {
    double priaPct = totalJemaatDaerah == 0 ? 0 : (pria / totalJemaatDaerah) * 100;
    double wanitaPct = totalJemaatDaerah == 0 ? 0 : (wanita / totalJemaatDaerah) * 100;

    return Container(
      height: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: totalJemaatDaerah == 0 
        ? const Center(child: Text("Belum ada jemaat", style: TextStyle(color: Colors.grey)))
        : Row(
            children: [
              Expanded(
                child: PieChart(
                  PieChartData(
                    sections: [
                      PieChartSectionData(value: pria.toDouble(), color: Colors.blue, title: "${priaPct.toStringAsFixed(1)}%", radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                      PieChartSectionData(value: wanita.toDouble(), color: Colors.pink, title: "${wanitaPct.toStringAsFixed(1)}%", radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: totalJemaatDaerah == 0 
        ? const Center(child: Text("Belum ada jemaat", style: TextStyle(color: Colors.grey)))
        : BarChart(
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
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(kategorialStats.keys.toList()[value.toInt()].substring(0, 3), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
            ),
          ),
    );
  }

  Widget _indicator(Color color, String text) {
    return Row(children: [Container(width: 12, height: 12, color: color), const SizedBox(width: 8), Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))]);
  }
}