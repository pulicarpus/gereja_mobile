import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import 'user_manager.dart';
import 'laporan_transaksi_page.dart';
import 'laporan_perpuluhan_page.dart';

class KeuanganPage extends StatefulWidget {
  final String? filterKategorial;
  const KeuanganPage({super.key, this.filterKategorial});

  @override
  State<KeuanganPage> createState() => _KeuanganPageState();
}

class _KeuanganPageState extends State<KeuanganPage> {
  final _db = FirebaseFirestore.instance;
  
  late int _selectedYear;
  List<int> _availableYears = [];

  bool _isLoading = false;
  int _totalPemasukan = 0;
  int _totalPengeluaran = 0;
  
  List<int> _pemasukanBulanan = List.filled(12, 0);
  List<int> _pengeluaranBulanan = List.filled(12, 0);
  List<int> _saldoBulanan = List.filled(12, 0); // 👈 VARIABEL BARU

  final List<String> _months = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Ags", "Sep", "Okt", "Nov", "Des"];

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
    _setupYears();
    _loadDataForYear(_selectedYear);
  }

  void _setupYears() {
    int currentYear = DateTime.now().year;
    _availableYears = List.generate(currentYear - 2020 + 1, (index) => currentYear - index);
  }

  Future<void> _loadDataForYear(int year) async {
    setState(() => _isLoading = true);
    
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) {
      setState(() => _isLoading = false);
      return;
    }

    DateTime startDate = DateTime(year, 1, 1);
    DateTime endDate = DateTime(year, 12, 31, 23, 59, 59);

    int tempPemasukan = 0;
    int tempPengeluaran = 0;
    List<int> tempPemBulanan = List.filled(12, 0);
    List<int> tempPengBulanan = List.filled(12, 0);
    List<int> tempSaldoBulanan = List.filled(12, 0);

    try {
      var churchRef = _db.collection("churches").doc(churchId);

      // 1. QUERY TRANSAKSI
      var trxQuery = await churchRef.collection("transaksi")
          .where("tanggal", isGreaterThanOrEqualTo: startDate)
          .where("tanggal", isLessThanOrEqualTo: endDate)
          .get();

      for (var doc in trxQuery.docs) {
        var data = doc.data();
        String? kategori = data['kategori'] as String?;
        int jumlah = (data['jumlah'] ?? 0) as int;
        DateTime? tgl = (data['tanggal'] as Timestamp?)?.toDate();
        String jenis = data['jenis'] ?? "";

        if (widget.filterKategorial == null || widget.filterKategorial!.isEmpty) {
          if (kategori != null && kategori.isNotEmpty && kategori != "Umum") continue;
        } else {
          if (kategori != widget.filterKategorial) continue;
        }

        if (tgl != null) {
          int monthIndex = tgl.month - 1; 
          if (jenis == "Pemasukan") {
            tempPemasukan += jumlah;
            tempPemBulanan[monthIndex] += jumlah;
          } else {
            tempPengeluaran += jumlah;
            tempPengBulanan[monthIndex] += jumlah;
          }
        }
      }

      // 2. QUERY PERPULUHAN (Jika Umum)
      if (widget.filterKategorial == null || widget.filterKategorial!.isEmpty) {
        var perpQuery = await churchRef.collection("perpuluhan")
            .where("tanggal", isGreaterThanOrEqualTo: startDate)
            .where("tanggal", isLessThanOrEqualTo: endDate)
            .get();

        for (var doc in perpQuery.docs) {
          var data = doc.data();
          int jumlah = (data['jumlah'] ?? 0) as int;
          DateTime? tgl = (data['tanggal'] as Timestamp?)?.toDate();

          if (tgl != null) {
            int monthIndex = tgl.month - 1;
            tempPemasukan += jumlah;
            tempPemBulanan[monthIndex] += jumlah;
          }
        }
      }

      // HITUNG SALDO PER BULAN
      for (int i = 0; i < 12; i++) {
        tempSaldoBulanan[i] = tempPemBulanan[i] - tempPengBulanan[i];
      }

      if (mounted) {
        setState(() {
          _totalPemasukan = tempPemasukan;
          _totalPengeluaran = tempPengeluaran;
          _pemasukanBulanan = tempPemBulanan;
          _pengeluaranBulanan = tempPengBulanan;
          _saldoBulanan = tempSaldoBulanan;
        });
      }
    } catch (e) {
      debugPrint("Error mengambil data keuangan: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String formatRupiah(int amount) {
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);
  }

  void _openLaporan(String tipe) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => LaporanTransaksiPage(tipeFilter: tipe, filterKategorial: widget.filterKategorial,))).then((_) => _loadDataForYear(_selectedYear));
  }

  void _openPerpuluhan() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LaporanPerpuluhanPage())).then((_) => _loadDataForYear(_selectedYear));
  }

  @override
  Widget build(BuildContext context) {
    bool isKategorial = widget.filterKategorial != null && widget.filterKategorial!.isNotEmpty;
    int saldoTotal = _totalPemasukan - _totalPengeluaran;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(isKategorial ? "Keuangan ${widget.filterKategorial}" : "Laporan Keuangan Gereja", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF075E54))) 
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. FILTER TAHUN
                _buildYearFilter(),
                const SizedBox(height: 20),

                // 2. KARTU SALDO UTAMA
                _buildMainBalanceCard(saldoTotal),
                const SizedBox(height: 30),

                // 3. GRAFIK BULANAN
                const Text("Grafik Bulanan", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                SizedBox(height: 250, child: _buildBarChart()),
                const SizedBox(height: 30),

                // 4. RINCIAN SALDO PER BULAN (FITUR BARU)
                const Text("Rincian Saldo Per Bulan", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                _buildMonthlyDetailsList(),
                const SizedBox(height: 35),

                // 5. TOMBOL NAVIGASI
                _buildNavButtons(isKategorial),
                const SizedBox(height: 40),
              ],
            ),
          ),
    );
  }

  Widget _buildYearFilter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("Pilih Tahun:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedYear,
              items: _availableYears.map((year) => DropdownMenuItem(value: year, child: Text(year.toString(), style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
              onChanged: (val) { if (val != null) { setState(() => _selectedYear = val); _loadDataForYear(val); } },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMainBalanceCard(int saldoTotal) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text("Total Saldo Tahun Ini", style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 5),
            Text(formatRupiah(saldoTotal), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue)),
            const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider(height: 1, thickness: 1)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSummaryColumn("Pemasukan", _totalPemasukan, Colors.green),
                _buildSummaryColumn("Pengeluaran", _totalPengeluaran, Colors.red, isEnd: true),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryColumn(String label, int amount, Color color, {bool isEnd = false}) {
    return Column(
      crossAxisAlignment: isEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(formatRupiah(amount), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildMonthlyDetailsList() {
    // Hanya tampilkan bulan yang sudah lewat atau ada transaksinya
    int currentMonthIndex = _selectedYear == DateTime.now().year ? DateTime.now().month - 1 : 11;
    
    return Column(
      children: List.generate(currentMonthIndex + 1, (index) {
        int saldo = _saldoBulanan[index];
        bool isPositive = saldo >= 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_months[index], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isPositive ? "+${formatRupiah(saldo)}" : formatRupiah(saldo),
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      color: isPositive ? Colors.green : Colors.red,
                      fontSize: 15
                    ),
                  ),
                  Text(
                    "Masuk: ${formatRupiah(_pemasukanBulanan[index])}",
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  )
                ],
              )
            ],
          ),
        );
      }).reversed.toList(), // Tampilkan dari bulan terbaru
    );
  }

  Widget _buildNavButtons(bool isKategorial) {
    return Column(
      children: [
        _buildActionButton(Icons.arrow_downward, "Lihat Data Pemasukan", Colors.green, () => _openLaporan("Pemasukan")),
        const SizedBox(height: 12),
        _buildActionButton(Icons.arrow_upward, "Lihat Data Pengeluaran", Colors.red, () => _openLaporan("Pengeluaran")),
        const SizedBox(height: 12),
        if (!isKategorial)
          _buildActionButton(Icons.volunteer_activism, "Laporan Perpuluhan", Colors.purple, _openPerpuluhan),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onPressed) {
    return ElevatedButton.icon(
      icon: Icon(icon, color: color),
      label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 15), 
        backgroundColor: color.withOpacity(0.05),
        elevation: 0,
        side: BorderSide(color: color.withOpacity(0.2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        minimumSize: const Size(double.infinity, 50)
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildBarChart() {
    double maxVal = 0;
    for (int i = 0; i < 12; i++) {
      if (_pemasukanBulanan[i] > maxVal) maxVal = _pemasukanBulanan[i].toDouble();
      if (_pengeluaranBulanan[i] > maxVal) maxVal = _pengeluaranBulanan[i].toDouble();
    }
    if (maxVal == 0) maxVal = 10000; 

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxVal * 1.2, 
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${_months[group.x]}\n${rodIndex == 0 ? "Masuk" : "Keluar"}: ${formatRupiah(rod.toY.toInt())}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) => Padding(padding: const EdgeInsets.only(top: 8), child: Text(_months[val.toInt()], style: const TextStyle(fontSize: 10, color: Colors.grey))))),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), 
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxVal / 4, getDrawingHorizontalLine: (val) => FlLine(color: Colors.grey.shade200, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(12, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(toY: _pemasukanBulanan[i].toDouble(), color: Colors.green, width: 8, borderRadius: BorderRadius.circular(4)),
              BarChartRodData(toY: _pengeluaranBulanan[i].toDouble(), color: Colors.red, width: 8, borderRadius: BorderRadius.circular(4)),
            ],
          );
        }),
      ),
    );
  }
}