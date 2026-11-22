import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import 'user_manager.dart';
import 'app_safety.dart';
import 'laporan_transaksi_page.dart';
import 'laporan_perpuluhan_page.dart';
import 'loading_sultan.dart';
import 'kategorial_config.dart';
import 'finance_running_balance.dart';

class KeuanganPage extends StatefulWidget {
  final String? filterKategorial;
  const KeuanganPage({super.key, this.filterKategorial});

  @override
  State<KeuanganPage> createState() => _KeuanganPageState();
}

class _KeuanganPageState extends State<KeuanganPage> {
  final _db = FirebaseFirestore.instance;
  
  late int _selectedYear;
  late int _selectedDetailMonth; // 👈 VARIABEL BARU UNTUK DROPDOWN BULAN
  
  List<int> _availableYears = [];

  bool _isLoading = false;
  bool _previewLoading = false;
  String? _loadError;
  int _loadGeneration = 0;
  int _totalPemasukan = 0;
  int _totalPengeluaran = 0;
  
  List<int> _pemasukanBulanan = List.filled(12, 0);
  List<int> _pengeluaranBulanan = List.filled(12, 0);
  List<int> _saldoBulanan = List.filled(12, 0); 

  final List<String> _months = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];
  final List<String> _shortMonths = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Ags", "Sep", "Okt", "Nov", "Des"];

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
    _selectedDetailMonth = DateTime.now().month - 1; // Default ke bulan saat ini
    _setupYears();
    _loadDataForYear(_selectedYear);
  }

  void _setupYears() {
    int currentYear = DateTime.now().year;
    _availableYears = List.generate(currentYear - 2020 + 1, (index) => currentYear - index);
  }

  bool _matchesKategori(dynamic raw) {
    final filter = widget.filterKategorial?.trim();
    final kategori = raw?.toString().trim() ?? "";
    if (filter == null || filter.isEmpty) {
      return kategori.isEmpty ||
          kategori.toLowerCase() == "umum";
    }
    return KategorialConfig.same(kategori, filter);
  }

  DateTime? _readDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  Future<void> _loadDataForYear(int year) async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
        _totalPemasukan = 0;
        _totalPengeluaran = 0;
        _pemasukanBulanan = List.filled(12, 0);
        _pengeluaranBulanan = List.filled(12, 0);
        _saldoBulanan = List.filled(12, 0);
      });
    }
    
    final churchId = UserManager().getChurchIdForCurrentView();
    if (churchId == null || churchId.isEmpty) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _isLoading = false;
          _loadError = "Data gereja tidak valid.";
        });
      }
      return;
    }

    DateTime startDate = DateTime(year, 1, 1);
    DateTime endDate = DateTime(year + 1, 1, 1);

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
          .where("tanggal", isLessThan: endDate)
          .get().timeout(const Duration(seconds: 20));

      for (var doc in trxQuery.docs) {
        var data = doc.data();
        final kategori = data['kategori'];
        int jumlah = legacyAmount(data['jumlah']) ?? 0;
        DateTime? tgl = _readDate(data['tanggal']);
        String jenis = data['jenis']?.toString().trim() ?? "";

        if (!_matchesKategori(kategori)) continue;

        if (tgl != null) {
          int monthIndex = tgl.month - 1; 
          if (jenis == "Pemasukan") {
            tempPemasukan += jumlah;
            tempPemBulanan[monthIndex] += jumlah;
          } else if (jenis == "Pengeluaran") {
            tempPengeluaran += jumlah;
            tempPengBulanan[monthIndex] += jumlah;
          }
        }
      }

      // 2. QUERY PERPULUHAN (Jika Umum)
      if (widget.filterKategorial == null || widget.filterKategorial!.isEmpty) {
        var perpQuery = await churchRef.collection("perpuluhan")
            .where("tanggal", isGreaterThanOrEqualTo: startDate)
            .where("tanggal", isLessThan: endDate)
            .get().timeout(const Duration(seconds: 20));

        for (var doc in perpQuery.docs) {
          var data = doc.data();
          int jumlah = legacyAmount(data['jumlah']) ?? 0;
          DateTime? tgl = _readDate(data['tanggal']);

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

      if (mounted && generation == _loadGeneration) {
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
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadError = "Gagal memuat data keuangan. Jangan gunakan angka ini untuk laporan.");
      }
    } finally {
      if (mounted && generation == _loadGeneration) setState(() => _isLoading = false);
    }
  }

  /// Read-only preview. This does not post transfers or alter Firestore data.
  Future<void> _showCashBalancePreview() async {
    if (_previewLoading || _isLoading) return;
    final churchId = UserManager().getChurchIdForCurrentView();
    if (churchId == null || churchId.isEmpty) return;
    setState(() => _previewLoading = true);
    try {
      final start = DateTime(2020, 1, 1);
      final end = DateTime(_selectedYear + 1, 1, 1);
      final church = _db.collection('churches').doc(churchId);
      final trxSnapshot = await church.collection('transaksi')
          .where('tanggal', isGreaterThanOrEqualTo: start)
          .where('tanggal', isLessThan: end)
          .get().timeout(const Duration(seconds: 20));
      final entries = <CashLedgerEntry>[];
      var invalid = 0;
      for (final doc in trxSnapshot.docs) {
        final d = doc.data();
        if (!_matchesKategori(d['kategori'])) continue;
        final date = _readDate(d['tanggal']);
        final amount = legacyAmount(d['jumlah']);
        final type = d['jenis']?.toString().trim() ?? '';
        if (date == null || amount == null || amount < 0 ||
            (type != 'Pemasukan' && type != 'Pengeluaran')) {
          invalid++;
          continue;
        }
        entries.add(CashLedgerEntry(
          date: date, description: d['keterangan']?.toString() ?? '',
          income: type == 'Pemasukan', amount: amount,
        ));
      }
      if (widget.filterKategorial == null ||
          widget.filterKategorial!.trim().isEmpty) {
        final titheSnapshot = await church.collection('perpuluhan')
            .where('tanggal', isGreaterThanOrEqualTo: start)
            .where('tanggal', isLessThan: end)
            .get().timeout(const Duration(seconds: 20));
        for (final doc in titheSnapshot.docs) {
          final d = doc.data();
          final date = _readDate(d['tanggal']);
          final amount = legacyAmount(d['jumlah']);
          if (date == null || amount == null || amount < 0) {
            invalid++;
            continue;
          }
          entries.add(CashLedgerEntry(
            date: date, description: 'Perpuluhan',
            income: true, amount: amount, isTithe: true,
          ));
        }
      }
      final result = calculateCashRunningBalance(
        entries, selectedYear: _selectedYear, asOf: DateTime.now());
      if (!mounted) return;
      _renderCashBalancePreview(result, invalid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Gagal menghitung pratinjau saldo. Data tidak diubah.'),
        ));
      }
      debugPrint('Read-only finance preview failed: $e');
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  void _renderCashBalancePreview(CashAuditResult audit, int invalidRows) {
    final months = audit.months.where((m) => m.year == _selectedYear).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.88,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('PRATINJAU SALDO BERJALAN (READ-ONLY)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 6),
              const Text('Transaksi dan laporan utama tidak diubah. '
                  'Entri saldo awal manual dipisahkan dari penerimaan baru.'),
              const SizedBox(height: 12),
              if (!audit.hasDocumentedOpening)
                const Text('PERINGATAN: saldo pembuka belum ditemukan; '
                    'hasil kas berjalan belum dapat dipastikan.',
                    style: TextStyle(color: Colors.red)),
              Text('Pemasukan baru: ' + formatRupiah(
                  months.fold<int>(0, (sum, m) => sum + m.income))),
              Text('Pengeluaran: ' + formatRupiah(
                  months.fold<int>(0, (sum, m) => sum + m.expense))),
              Text('Surplus/defisit operasional: ' + formatRupiah(
                  months.fold<int>(0, (sum, m) => sum + m.net))),
              if (months.isNotEmpty)
                Text('Saldo akhir: ' + formatRupiah(months.last.closing),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              if (invalidRows > 0)
                Text('Ada ' + invalidRows.toString() +
                    ' transaksi tidak valid yang tidak dihitung.',
                    style: const TextStyle(color: Colors.red)),
              for (final warning in audit.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('⚠ ' + warning,
                      style: const TextStyle(color: Colors.deepOrange)),
                ),
              const Divider(height: 30),
              for (final month in months)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_months[month.month - 1] + ' ' +
                          month.year.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Saldo awal: ' + formatRupiah(month.opening)),
                        Text('Pemasukan baru: ' + formatRupiah(month.income)),
                        Text('Pengeluaran: ' + formatRupiah(month.expense)),
                        Text('Surplus/defisit: ' + formatRupiah(month.net)),
                        Text('Saldo akhir: ' + formatRupiah(month.closing),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (month.manualCarryCount > 0)
                          Text('Saldo manual: ' + formatRupiah(month.manualCarry) +
                              ' | Selisih: ' + formatRupiah(month.manualDifference),
                              style: TextStyle(
                                color: month.manualDifference == 0
                                    ? Colors.green : Colors.red)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const Text('Pratinjau perlu dicocokkan dengan saldo kas/rekening '
                  'bendahara sebelum dijadikan laporan resmi.'),
            ],
          ),
        ),
      ),
    );
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
        ? LoadingSultan(size: 80)
        : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 54, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _loadDataForYear(_selectedYear),
                      child: const Text("COBA LAGI"),
                    ),
                  ],
                ),
              ),
            )
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
                const SizedBox(height: 35),

                // 4. RINCIAN SALDO PER BULAN (SEKARANG PAKAI DROPDOWN)
                const Text("Rincian Saldo Bulanan", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                _buildMonthlyDetailSection(), // 👈 FUNGSI BARU DIPANGGIL DI SINI
                const SizedBox(height: 35),

                // 5. TOMBOL NAVIGASI
                _buildActionButton(
                  Icons.account_balance_wallet_outlined,
                  _previewLoading
                      ? 'Menghitung saldo berjalan...'
                      : 'Pratinjau Saldo Berjalan (Read-only)',
                  Colors.teal,
                  () { _showCashBalancePreview(); },
                ),
                const SizedBox(height: 12),
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
            Text("Surplus / Defisit Tahun $_selectedYear", style: const TextStyle(color: Colors.grey, fontSize: 14)),
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

  // 👇 FUNGSI BARU: KARTU RINCIAN DENGAN DROPDOWN BULAN 👇
  Widget _buildMonthlyDetailSection() {
    int saldo = _saldoBulanan[_selectedDetailMonth];
    int masuk = _pemasukanBulanan[_selectedDetailMonth];
    int keluar = _pengeluaranBulanan[_selectedDetailMonth];
    bool isPositive = saldo >= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Baris Dropdown Bulan
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Pilih Bulan:", style: TextStyle(color: Colors.grey, fontSize: 14)),
              Container(
                height: 35,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300)
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedDetailMonth,
                    icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                    items: List.generate(12, (index) {
                      return DropdownMenuItem(
                        value: index,
                        child: Text(_months[index], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      );
                    }),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedDetailMonth = val);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Divider(height: 1, thickness: 1),
          ),
          
          // Rincian Angka
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Pemasukan", style: TextStyle(fontSize: 14, color: Colors.grey)),
              Text(formatRupiah(masuk), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Pengeluaran", style: TextStyle(fontSize: 14, color: Colors.grey)),
              Text(formatRupiah(keluar), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isPositive ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(8)
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Arus Bersih Bulan", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isPositive ? Colors.green.shade800 : Colors.red.shade800)),
                Text(
                  isPositive ? "+${formatRupiah(saldo)}" : formatRupiah(saldo),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isPositive ? Colors.green.shade800 : Colors.red.shade800),
                ),
              ],
            ),
          ),
        ],
      ),
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
                '${_shortMonths[group.x]}\n${rodIndex == 0 ? "Masuk" : "Keluar"}: ${formatRupiah(rod.toY.toInt())}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) => Padding(padding: const EdgeInsets.only(top: 8), child: Text(_shortMonths[val.toInt()], style: const TextStyle(fontSize: 10, color: Colors.grey))))),
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
