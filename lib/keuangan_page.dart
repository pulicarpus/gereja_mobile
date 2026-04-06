import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart'; // Library Grafik Pengganti MPAndroidChart

import 'user_manager.dart';
// Note: Jangan lupa sesuaikan import halaman ini nanti kalau sudah dibuat
// import 'laporan_transaksi_page.dart';
// import 'laporan_perpuluhan_page.dart';

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
    // Buat daftar tahun dari 2020 sampai tahun sekarang (Meniru logika Kotlin)
    _availableYears = List.generate(currentYear - 2020 + 1, (index) => currentYear - index);
  }

  // --- LOGIKA FILTER KETAT (Translasi dari Kotlin) ---
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

        // LOGIKA KETAT: Pisahkan Umum dan Kategorial
        if (widget.filterKategorial == null || widget.filterKategorial!.isEmpty) {
          // MODE UMUM: Abaikan jika dokumen punya kategori selain "Umum"
          if (kategori != null && kategori.isNotEmpty && kategori != "Umum") continue;
        } else {
          // MODE KATEGORIAL: Hanya ambil yang kategorinya cocok
          if (kategori != widget.filterKategorial) continue;
        }

        if (tgl != null) {
          int monthIndex = tgl.month - 1; // 0 = Jan, 11 = Des
          if (jenis == "Pemasukan") {
            tempPemasukan += jumlah;
            tempPemBulanan[monthIndex] += jumlah;
          } else {
            tempPengeluaran += jumlah;
            tempPengBulanan[monthIndex] += jumlah;
          }
        }
      }

      // 2. QUERY PERPULUHAN (Hanya jika Mode Kas Umum)
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

      // Update State UI
      if (mounted) {
        setState(() {
          _totalPemasukan = tempPemasukan;
          _totalPengeluaran = tempPengeluaran;
          _pemasukanBulanan = tempPemBulanan;
          _pengeluaranBulanan = tempPengBulanan;
        });
      }
    } catch (e) {
      print("Error mengambil data keuangan: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String formatRupiah(int amount) {
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);
  }

  // --- FUNGSI NAVIGASI ---
  void _openLaporan(String tipe) {
    // Navigator.push(context, MaterialPageRoute(builder: (_) => LaporanTransaksiPage(
    //   tipeTransaksi: tipe,
    //   filterKategorial: widget.filterKategorial,
    // )));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Buka Laporan $tipe")));
  }

  void _openPerpuluhan() {
    // Navigator.push(context, MaterialPageRoute(builder: (_) => LaporanPerpuluhanPage()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Buka Laporan Perpuluhan")));
  }

  @override
  Widget build(BuildContext context) {
    bool isKategorial = widget.filterKategorial != null && widget.filterKategorial!.isNotEmpty;
    int saldo = _totalPemasukan - _totalPengeluaran;

    return Scaffold(
      appBar: AppBar(
        title: Text(isKategorial ? "Keuangan ${widget.filterKategorial}" : "Laporan Keuangan Gereja"),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. SPINNER TAHUN (Dropdown)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Pilih Tahun:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    DropdownButton<int>(
                      value: _selectedYear,
                      items: _availableYears.map((year) {
                        return DropdownMenuItem(value: year, child: Text(year.toString()));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedYear = val);
                          _loadDataForYear(val);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 2. KARTU SALDO & SUMMARY
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text("Total Saldo", style: TextStyle(color: Colors.grey, fontSize: 16)),
                        const SizedBox(height: 5),
                        Text(formatRupiah(saldo), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blue)),
                        const Divider(height: 30, thickness: 1),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Pemasukan", style: TextStyle(color: Colors.grey)),
                                Text(formatRupiah(_totalPemasukan), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text("Pengeluaran", style: TextStyle(color: Colors.grey)),
                                Text(formatRupiah(_totalPengeluaran), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // 3. GRAFIK BATANG (Bar Chart)
                const Text("Grafik Bulanan", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                SizedBox(
                  height: 250,
                  child: _buildBarChart(),
                ),
                const SizedBox(height: 30),

                // 4. TOMBOL NAVIGASI
                ElevatedButton.icon(
                  icon: const Icon(Icons.arrow_downward, color: Colors.green),
                  label: const Text("Lihat Data Pemasukan", style: TextStyle(color: Colors.green)),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), backgroundColor: Colors.green.shade50),
                  onPressed: () => _openLaporan("Pemasukan"),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.arrow_upward, color: Colors.red),
                  label: const Text("Lihat Data Pengeluaran", style: TextStyle(color: Colors.red)),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), backgroundColor: Colors.red.shade50),
                  onPressed: () => _openLaporan("Pengeluaran"),
                ),
                const SizedBox(height: 10),
                
                // Tombol Perpuluhan (Hanya muncul jika bukan kategorial)
                if (!isKategorial)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.volunteer_activism, color: Colors.purple),
                    label: const Text("Laporan Perpuluhan", style: TextStyle(color: Colors.purple)),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), backgroundColor: Colors.purple.shade50),
                    onPressed: _openPerpuluhan,
                  ),
              ],
            ),
          ),
    );
  }

  // WIDGET GRAFIK BATANG (Translasi dari MPAndroidChart ke fl_chart)
  Widget _buildBarChart() {
    double maxVal = 0;
    for (int i = 0; i < 12; i++) {
      if (_pemasukanBulanan[i] > maxVal) maxVal = _pemasukanBulanan[i].toDouble();
      if (_pengeluaranBulanan[i] > maxVal) maxVal = _pengeluaranBulanan[i].toDouble();
    }
    if (maxVal == 0) maxVal = 10000; // Default skala jika kosong

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxVal * 1.2, // Kasih ruang sedikit di atas
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(_months[value.toInt()], style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // Sembunyikan angka ribet di kiri
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(12, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              // Batang Hijau (Pemasukan)
              BarChartRodData(toY: _pemasukanBulanan[i].toDouble(), color: Colors.green, width: 8, borderRadius: BorderRadius.circular(2)),
              // Batang Merah (Pengeluaran)
              BarChartRodData(toY: _pengeluaranBulanan[i].toDouble(), color: Colors.red, width: 8, borderRadius: BorderRadius.circular(2)),
            ],
          );
        }),
      ),
    );
  }
}