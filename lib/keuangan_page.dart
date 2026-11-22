import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
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
import 'finance_full_export.dart';

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
  bool _exportBusy = false;
  bool _openingBusy = false;
  CashAuditResult? _automaticBalance;
  int _automaticInvalidRows = 0;
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
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
      _automaticBalance = null;
      _automaticInvalidRows = 0;
      _totalPemasukan = 0;
      _totalPengeluaran = 0;
      _pemasukanBulanan = List<int>.filled(12, 0);
      _pengeluaranBulanan = List<int>.filled(12, 0);
      _saldoBulanan = List<int>.filled(12, 0);
    });
    try {
      // A single audited ledger is the source for the annual card, chart,
      // and monthly details. It excludes legacy opening rows from new income.
      final data = await _fetchCashBalanceAudit(year);
      if (!mounted || generation != _loadGeneration) return;
      final income = List<int>.filled(12, 0);
      final expense = List<int>.filled(12, 0);
      final net = List<int>.filled(12, 0);
      for (final month in data.audit.months) {
        if (month.year != year) continue;
        final index = month.month - 1;
        income[index] = month.income;
        expense[index] = month.expense;
        net[index] = month.net;
      }
      final summary = summarizeCashYear(data.audit, year);
      setState(() {
        _automaticBalance = data.audit;
        _automaticInvalidRows = data.invalidRows;
        _totalPemasukan = summary?.income ?? 0;
        _totalPengeluaran = summary?.expense ?? 0;
        _pemasukanBulanan = income;
        _pengeluaranBulanan = expense;
        _saldoBulanan = net;
      });
    } catch (e) {
      debugPrint('Gagal memuat saldo berjalan: $e');
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loadError = 'Gagal memuat laporan saldo berjalan. '
              'Tidak ada saldo yang dianggap valid.';
        });
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Membaca data untuk audit; tidak menyimpan transaksi saldo bawaan.

  Future<({CashAuditResult audit, int invalidRows, List<CashLedgerEntry> entries})>
      _fetchCashBalanceAudit(int year) async {
    final churchId = UserManager().getChurchIdForCurrentView();
    if (churchId == null || churchId.isEmpty) {
      throw StateError('Gereja tidak tersedia');
    }
    final start = DateTime(2020, 1, 1);
    final end = DateTime(year + 1, 1, 1);
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
      final opening = d['saldoPembuka'] == true || type == 'Saldo Pembuka';
      if (date == null || amount == null || amount < 0 ||
          (!opening && type != 'Pemasukan' && type != 'Pengeluaran')) {
        invalid++;
        continue;
      }
      entries.add(CashLedgerEntry(
        date: date, description: d['keterangan']?.toString() ?? '',
        income: type == 'Pemasukan', amount: amount,
        isOpeningBalance: opening,
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
          giverName: (d['namaJemaat'] ?? 'Tanpa Nama').toString(),
          giverId: d['jemaatId']?.toString(),
        ));
      }
    }
    return (
      audit: calculateCashRunningBalance(
        entries, selectedYear: year, asOf: DateTime.now()),
      invalidRows: invalid,
      entries: entries,
    );
  }

  Future<void> _showCashBalancePreview() async {
    if (_previewLoading || _isLoading) return;
    setState(() => _previewLoading = true);
    try {
      if (_automaticBalance != null) {
        _renderCashBalancePreview(_automaticBalance!, _automaticInvalidRows);
      } else {
        final data = await _fetchCashBalanceAudit(_selectedYear);
        if (!mounted) return;
        _renderCashBalancePreview(data.audit, data.invalidRows);
      }
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


  bool _canExportCompleteReport() {
    final user = UserManager();
    final filter = widget.filterKategorial?.trim();
    return user.isAdmin() ||
        (filter != null && filter.isNotEmpty && user.isPengurus &&
            KategorialConfig.same(user.userKomisi, filter));
  }

  Future<void> _showCompleteExportDialog() async {
    if (_exportBusy || _isLoading || !_canExportCompleteReport()) return;
    var period = FinanceExportPeriod.oneMonth;
    var format = 'pdf';
    final choice = await showDialog<({FinanceExportPeriod period, String format})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Ekspor Laporan Keuangan Lengkap'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tahun: ' + _selectedYear.toString()),
              const SizedBox(height: 12),
              const Text('Periode laporan:'),
              DropdownButton<FinanceExportPeriod>(
                value: period,
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                    value: FinanceExportPeriod.oneMonth,
                    child: Text('Satu bulan: ' +
                        _months[_selectedDetailMonth])),
                  const DropdownMenuItem(
                    value: FinanceExportPeriod.allMonths,
                    child: Text('Semua bulan (rinci per bulan)')),
                  const DropdownMenuItem(
                    value: FinanceExportPeriod.oneYear,
                    child: Text('Gabungan satu tahun')),
                ],
                onChanged: (value) {
                  if (value != null) update(() => period = value);
                },
              ),
              const SizedBox(height: 12),
              const Text('Format file:'),
              DropdownButton<String>(
                value: format,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'pdf', child: Text('PDF - Siap cetak')),
                  DropdownMenuItem(value: 'csv', child: Text('CSV - Data tabel')),
                ],
                onChanged: (value) {
                  if (value != null) update(() => format = value);
                },
              ),
              const SizedBox(height: 8),
              const Text('Isi: pemasukan asli, pengeluaran, tabel '
                  'perpuluhan per penyetor, saldo bawaan dan saldo akhir. '
                  'Perpuluhan dihitung satu kali dalam total pemasukan.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              const Text('Dokumen ini berisi data keuangan dan mungkin '
                  'nama penyetor perpuluhan. Bagikan hanya kepada '
                  'pihak berwenang.',
                  style: TextStyle(fontSize: 12, color: Colors.deepOrange)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext,
                  (period: period, format: format)),
              child: const Text('Ekspor')),
          ],
        ),
      ),
    );
    if (choice != null && mounted) {
      await _exportCompleteReport(choice.period, choice.format);
    }
  }

  Future<void> _exportCompleteReport(
      FinanceExportPeriod period, String format) async {
    if (_exportBusy || _isLoading || !_canExportCompleteReport()) return;
    final year = _selectedYear;
    final month = _selectedDetailMonth + 1;
    setState(() => _exportBusy = true);
    try {
      final data = await _fetchCashBalanceAudit(year);
      if (!mounted) return;
      final user = UserManager();
      final church = user.activeChurchName ?? user.originalChurchName ??
          'Gereja';
      final name = widget.filterKategorial == null ||
              widget.filterKategorial!.trim().isEmpty
          ? church
          : church + ' - ' + widget.filterKategorial!;
      final report = createFinanceCompleteReport(
        churchName: name,
        year: year,
        month: month,
        period: period,
        audit: data.audit,
        entries: data.entries,
        invalidRows: data.invalidRows,
      );
      if (report.sections.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Belum ada data pada periode yang dipilih.'),
        ));
        return;
      }
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        throw StateError('Penyimpanan tidak tersedia.');
      }
      final suffix = DateTime.now().millisecondsSinceEpoch;
      final filename = 'GKII_Keuangan_' + year.toString() + '_' +
          period.name + '_' + suffix.toString() + '.' + format;
      final output = File(dir.path + '/' + filename);
      if (format == 'pdf') {
        await output.writeAsBytes(await financeCompletePdf(report),
            flush: true);
      } else {
        await output.writeAsString(financeCompleteCsv(report), flush: true);
      }
      final opened = await OpenFilex.open(output.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(opened.type == ResultType.error
            ? 'Laporan dibuat di penyimpanan aplikasi, '
                'tetapi belum dapat dibuka otomatis.'
            : 'Laporan lengkap berhasil dibuat.'),
      ));
    } catch (e) {
      debugPrint('Finance complete export failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ekspor gagal. Tidak ada transaksi yang diubah.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _exportBusy = false);
    }
  }

  Future<void> _showOpeningBalanceDialog() async {
    if (_openingBusy || _isLoading || !UserManager().isAdmin()) return;
    final year = _selectedYear;
    final month = _selectedDetailMonth + 1;
    final amountCtrl = TextEditingController();
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Saldo Pembuka Gereja Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Periode: ' + _months[month - 1] + ' ' + year.toString()),
            const SizedBox(height: 8),
            const Text('Masukkan uang kas/rekening yang benar-benar ada '
                'pada awal bulan pembukuan. Hanya sekali untuk kas ini. '
                'Bukan transaksi pemasukan.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Saldo pembuka (Rp)',
                hintText: 'Contoh: 1000000',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final amount = int.tryParse(amountCtrl.text.trim());
              if (amount == null || amount < 0) return;
              Navigator.pop(dialogContext, amount);
            },
            child: const Text('Simpan Saldo Pembuka'),
          ),
        ],
      ),
    );
    amountCtrl.dispose();
    if (value != null && mounted) {
      await _saveOpeningBalance(year, month, value);
    }
  }

  Future<void> _saveOpeningBalance(int year, int month, int amount) async {
    if (_openingBusy || amount < 0 || !UserManager().isAdmin()) return;
    final churchId = UserManager().getChurchIdForCurrentView();
    if (churchId == null || churchId.isEmpty) return;
    final category = widget.filterKategorial?.trim().isNotEmpty == true
        ? widget.filterKategorial!.trim() : 'Umum';
    setState(() => _openingBusy = true);
    try {
      final access = await ChurchWriteAccess.check(churchId,
          category: category);
      access.assertCurrent();
      final firstDay = DateTime(year, month, 1);
      final nextMonth = DateTime(year, month + 1, 1);
      final collection = _db.collection('churches').doc(churchId)
          .collection('transaksi');
      // Guard: do not retrofit a second opening into an active ledger.
      final existing = await collection.where('tanggal',
          isLessThan: nextMonth).get().timeout(const Duration(seconds: 20));
      for (final doc in existing.docs) {
        final record = doc.data();
        if (!_matchesKategori(record['kategori'])) continue;
        final rawDate = _readDate(record['tanggal']);
        if (rawDate == null) continue;
        final type = record['jenis']?.toString().trim() ?? '';
        final opening = record['saldoPembuka'] == true ||
            type == 'Saldo Pembuka' ||
            (type == 'Pemasukan' && isLegacyCashOpening(
                CashLedgerEntry(
                  date: rawDate,
                  description: record['keterangan']?.toString() ?? '',
                  income: true,
                  amount: legacyAmount(record['jumlah']) ?? 0,
                )));
        if (rawDate.isBefore(firstDay) || opening) {
          throw StateError('Kas ini sudah memiliki riwayat '
              'atau catatan saldo awal. Tidak boleh membuat pembuka baru.');
        }
      }
      if (widget.filterKategorial == null ||
          widget.filterKategorial!.trim().isEmpty) {
        final olderTithes = await _db.collection('churches').doc(churchId)
            .collection('perpuluhan')
            .where('tanggal', isLessThan: firstDay)
            .limit(1).get().timeout(const Duration(seconds: 20));
        if (olderTithes.docs.isNotEmpty) {
          throw StateError('Sudah ada perpuluhan sebelum bulan terpilih. '
              'Saldo pembuka harus ditetapkan sebelum periode pertama.');
        }
      }
      final uniqueId = 'saldo_pembuka_' +
          Uri.encodeComponent(category.toLowerCase());
      final target = collection.doc(uniqueId);
      await _db.runTransaction((tx) async {
        await access.inTransaction(tx);
        final current = await tx.get(target);
        if (current.exists) {
          throw StateError('Saldo pembuka sudah pernah disimpan.');
        }
        access.assertCurrent();
        tx.set(target, {
          'jenis': 'Saldo Pembuka',
          'saldoPembuka': true,
          'keterangan': 'Saldo pembuka resmi ' +
              _months[month - 1] + ' ' + year.toString(),
          'jumlah': amount,
          'tanggal': Timestamp.fromDate(firstDay),
          'kategori': category,
        });
      }).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Saldo pembuka disimpan satu kali. '
            'Tidak dicatat sebagai pemasukan.'),
      ));
      await _loadDataForYear(_selectedYear);
    } catch (e) {
      debugPrint('Opening balance setup failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Tidak dapat menyimpan saldo pembuka: ' +
              e.toString()),
        ));
      }
    } finally {
      if (mounted) setState(() => _openingBusy = false);
    }
  }

  void _renderCashBalancePreview(CashAuditResult audit, int invalidRows) {
    final months = audit.months.where((m) => m.year == _selectedYear).toList();
    final income = months.fold<int>(0, (sum, m) => sum + m.income);
    final expense = months.fold<int>(0, (sum, m) => sum + m.expense);
    final net = income - expense;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.88,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Saldo Berjalan $_selectedYear',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              if (!audit.hasDocumentedOpening)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Saldo pembuka belum ditemukan.',
                      style: TextStyle(color: Colors.red)),
                ),
              Text('Total pemasukan: ' + formatRupiah(income)),
              Text('Total pengeluaran: ' + formatRupiah(expense)),
              Text('Surplus/defisit: ' + formatRupiah(net)),
              if (months.isNotEmpty)
                Text('Saldo akhir: ' + formatRupiah(months.last.closing),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 20)),
              if (invalidRows > 0)
                Text('$invalidRows transaksi tidak valid tidak dihitung.',
                    style: const TextStyle(color: Colors.red)),
              for (final warning in audit.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('⚠ ' + warning,
                      style: const TextStyle(color: Colors.deepOrange)),
                ),
              const Divider(height: 24),
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
                        const SizedBox(height: 6),
                        Text('Saldo awal: ' + formatRupiah(month.opening)),
                        Text('Pemasukan: ' + formatRupiah(month.income)),
                        Text('Pengeluaran: ' + formatRupiah(month.expense)),
                        Text('Surplus/defisit: ' + formatRupiah(month.net)),
                        Text('Saldo akhir: ' + formatRupiah(month.closing),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        if (month.manualCarryCount > 0 &&
                            month.manualDifference != 0)
                          Text('Selisih saldo manual: ' +
                              formatRupiah(month.manualDifference),
                              style: const TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ),
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
                _buildMainBalanceCard(),
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

                // 5. EKSPOR GABUNGAN / SALDO PEMBUKA
                if (_canExportCompleteReport()) ...[
                  _buildActionButton(
                    Icons.file_download_outlined,
                    _exportBusy
                        ? 'Membuat laporan lengkap...'
                        : 'Ekspor Laporan Lengkap (PDF / CSV)',
                    Colors.indigo,
                    () { _showCompleteExportDialog(); },
                  ),
                  const SizedBox(height: 12),
                ],
                if (UserManager().isAdmin() &&
                    _automaticBalance?.hasDocumentedOpening == false) ...[
                  _buildActionButton(
                    Icons.account_balance_wallet_outlined,
                    _openingBusy
                        ? 'Menyimpan saldo pembuka...'
                        : 'Atur Saldo Pembuka (Gereja Baru)',
                    Colors.blueGrey,
                    () { _showOpeningBalanceDialog(); },
                  ),
                  const SizedBox(height: 12),
                ],
                // 6. TOMBOL NAVIGASI
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

  Widget _buildMainBalanceCard() {
    final report = _automaticBalance;
    final year = report == null ? null : summarizeCashYear(report, _selectedYear);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (year == null)
              const Text('Belum ada data saldo berjalan pada tahun ini.')
            else ...[
              Text('Saldo Akhir s.d. ${_months[year.lastMonth - 1]} '
                '$_selectedYear',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(formatRupiah(year.closing),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: year.closing < 0 ? Colors.red : Colors.blue,
                  ),
                ),
              ),
              if (!report!.hasDocumentedOpening)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Saldo pembuka belum terverifikasi. '
                    'Angka saldo akhir bersifat sementara.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
                ),
              if (report.warnings.any(
                (w) => w.startsWith('Selisih saldo awal manual') ||
                    w.startsWith('Ada lebih dari satu saldo awal manual')))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Ada saldo awal manual yang tidak cocok. '
                    'Periksa rincian sebelum memakai angka sebagai laporan resmi.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
                ),
              if (_automaticInvalidRows > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '$_automaticInvalidRows transaksi tidak valid tidak '
                    'dihitung dalam saldo berjalan.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 15),
                child: Divider(height: 1, thickness: 1),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Saldo awal periode',
                    style: TextStyle(fontSize: 13)),
                  Text(formatRupiah(year.opening),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSummaryColumn('Pemasukan asli', _totalPemasukan, Colors.green),
                  _buildSummaryColumn('Pengeluaran asli', _totalPengeluaran,
                    Colors.red, isEnd: true),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Surplus / Defisit tahun berjalan',
                    style: TextStyle(fontSize: 12)),
                  Text(formatRupiah(year.net),
                    style: TextStyle(fontWeight: FontWeight.bold,
                      color: year.net < 0 ? Colors.red : Colors.green)),
                ],
              ),
              const SizedBox(height: 7),
              const Text('Saldo bawaan dihitung sekali sebagai saldo awal, '
                  'bukan tambahan pemasukan/pengeluaran.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
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
    CashMonthBalance? automaticMonth;
    for (final item in _automaticBalance?.months ?? const <CashMonthBalance>[]) {
      if (item.year == _selectedYear &&
          item.month == _selectedDetailMonth + 1) {
        automaticMonth = item;
        break;
      }
    }
    // Bulanan selalu menunjukkan pemasukan/pengeluaran baru bulan itu.
    // Saldo awal/akhir ditampilkan terpisah dan tidak dihitung ulang sebagai
    // transaksi baru.
    final saldo = automaticMonth?.net ?? 0;
    final masuk = automaticMonth?.income ?? 0;
    final keluar = automaticMonth?.expense ?? 0;
    final isPositive = saldo >= 0;

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
          
          if (automaticMonth == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Belum ada data saldo berjalan untuk bulan ini.',
                style: TextStyle(color: Colors.deepOrange)),
            ),
          if (automaticMonth != null &&
              _automaticBalance?.hasDocumentedOpening == false)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('PERINGATAN: saldo awal bulan pertama belum '
                  'terverifikasi. Hasil saldo berjalan hanya perkiraan.',
                  style: TextStyle(color: Colors.deepOrange)),
            ),
          // Rincian asli bulan ini, tanpa saldo bawaan.
          if (automaticMonth != null) Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Pemasukan", style: TextStyle(fontSize: 14, color: Colors.grey)),
              Text(formatRupiah(masuk), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15)),
            ],
          ),
          if (automaticMonth != null) const SizedBox(height: 10),
          if (automaticMonth != null) Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Pengeluaran", style: TextStyle(fontSize: 14, color: Colors.grey)),
              Text(formatRupiah(keluar), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 15)),
            ],
          ),
          if (automaticMonth != null) const SizedBox(height: 15),
          if (automaticMonth != null) Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isPositive ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(8)
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Surplus / Defisit Bulan", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isPositive ? Colors.green.shade800 : Colors.red.shade800)),
                Text(
                  isPositive ? "+${formatRupiah(saldo)}" : formatRupiah(saldo),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isPositive ? Colors.green.shade800 : Colors.red.shade800),
                ),
              ],
            ),
          ),
          if (automaticMonth != null) ...[
            const Divider(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(child: Text('Saldo Awal (Bawaan)',
                  style: TextStyle(fontWeight: FontWeight.bold))),
                Text(formatRupiah(automaticMonth.opening),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: automaticMonth.opening < 0 ? Colors.red : Colors.black87)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(child: Text('Saldo Akhir (Otomatis)',
                  style: TextStyle(fontWeight: FontWeight.bold))),
                Text(formatRupiah(automaticMonth.closing),
                  style: TextStyle(
                    color: automaticMonth.closing < 0
                        ? Colors.red.shade800 : Colors.green.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  )),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Saldo akhir otomatis diteruskan ke bulan berikutnya, '
                'tanpa membuat transaksi pemasukan atau pengeluaran.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
            if (automaticMonth.closing < 0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Saldo negatif: periksa sumber pembiayaan atau transaksi '
                  'yang belum dicatat.',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            if (automaticMonth.manualCarryCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Saldo awal manual lama: '
                  + formatRupiah(automaticMonth.manualCarry)
                  + ' (tidak dihitung sebagai pemasukan baru). '
                  + (automaticMonth.manualDifference == 0
                      ? 'Sesuai dengan saldo otomatis.'
                      : 'SELISIH: '
                          + formatRupiah(automaticMonth.manualDifference)
                          + '. Perlu diperiksa sebelum dipakai resmi.'),
                  style: TextStyle(
                    fontSize: 12,
                    color: automaticMonth.manualDifference == 0
                        ? Colors.green.shade800 : Colors.red.shade800,
                  ),
                ),
              ),
          ],
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
