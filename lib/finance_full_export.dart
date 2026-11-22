import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'finance_running_balance.dart';

enum FinanceExportPeriod { oneMonth, allMonths, oneYear }

class FinanceTitheTotal {
  final String name;
  final int count;
  final int total;
  const FinanceTitheTotal(this.name, this.count, this.total);
}

class FinanceReportSection {
  final String title;
  final List<CashMonthBalance> months;
  final List<CashLedgerEntry> entries;
  const FinanceReportSection(this.title, this.months, this.entries);

  int get opening => months.first.opening;
  int get closing => months.last.closing;
  int get income => months.fold<int>(0, (v, m) => v + m.income);
  int get expense => months.fold<int>(0, (v, m) => v + m.expense);
  int get net => income - expense;
  List<CashLedgerEntry> get otherIncome => entries.where((e) =>
      e.income && !e.isTithe && !isLegacyCashOpening(e)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  List<CashLedgerEntry> get expenses => entries.where((e) =>
      !e.income && !isLegacyCashOpening(e)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  List<CashLedgerEntry> get tithes => entries.where((e) => e.isTithe).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  int get titheTotal => tithes.fold<int>(0, (v, e) => v + e.amount);
  int get otherIncomeTotal => income - titheTotal;

  List<FinanceTitheTotal> get titheByPerson {
    final names = <String, String>{};
    final amounts = <String, int>{};
    final counts = <String, int>{};
    for (final row in tithes) {
      final name = row.giverName?.trim().isNotEmpty == true
          ? row.giverName!.trim() : 'Tanpa Nama';
      final id = row.giverId?.trim();
      final key = id != null && id.isNotEmpty
          ? 'id:' + id : 'nama:' + name.toLowerCase();
      names[key] = name;
      amounts[key] = (amounts[key] ?? 0) + row.amount;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final rows = amounts.keys.map((key) =>
        FinanceTitheTotal(names[key]!, counts[key]!, amounts[key]!)).toList();
    rows.sort((a, b) => a.name.toLowerCase().compareTo(
        b.name.toLowerCase()));
    return rows;
  }
}

class FinanceCompleteReport {
  final String churchName;
  final int year;
  final FinanceExportPeriod period;
  final List<FinanceReportSection> sections;
  final FinanceReportSection? annual;
  final bool hasOpening;
  final List<String> warnings;
  final int invalidRows;
  const FinanceCompleteReport({
    required this.churchName, required this.year,
    required this.period, required this.sections,
    required this.annual, required this.hasOpening,
    required this.warnings, required this.invalidRows,
  });
}

const financeMonthNames = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

FinanceCompleteReport createFinanceCompleteReport({
  required String churchName,
  required int year,
  required int month,
  required FinanceExportPeriod period,
  required CashAuditResult audit,
  required Iterable<CashLedgerEntry> entries,
  int invalidRows = 0,
}) {
  if (month < 1 || month > 12) throw ArgumentError.value(month, 'month');
  final months = audit.months.where((m) => m.year == year).toList();
  final transactions = entries.where((e) => e.date.year == year &&
      e.amount >= 0 && !isLegacyCashOpening(e)).toList();
  FinanceReportSection makeSection(
      String label, List<CashMonthBalance> selected) {
    final monthIds = selected.map((m) => m.month).toSet();
    return FinanceReportSection(label, selected, transactions.where(
        (e) => monthIds.contains(e.date.month)).toList());
  }
  final annual = months.isEmpty ? null :
      makeSection('Rekap Tahun ' + year.toString(), months);
  final sections = <FinanceReportSection>[];
  switch (period) {
    case FinanceExportPeriod.oneMonth:
      final selected = months.where((m) => m.month == month).toList();
      if (selected.isNotEmpty) {
        sections.add(makeSection(
            financeMonthNames[month - 1] + ' ' + year.toString(), selected));
      }
    case FinanceExportPeriod.allMonths:
      for (final m in months) {
        sections.add(makeSection(financeMonthNames[m.month - 1] +
            ' ' + year.toString(), [m]));
      }
    case FinanceExportPeriod.oneYear:
      if (annual != null) sections.add(annual);
  }
  return FinanceCompleteReport(
    churchName: churchName, year: year, period: period,
    sections: sections, annual: annual,
    hasOpening: audit.hasDocumentedOpening,
    warnings: audit.warnings, invalidRows: invalidRows,
  );
}

String _money(int amount) =>
    'Rp ' + NumberFormat.decimalPattern('id_ID').format(amount);
String _date(DateTime date) => DateFormat('dd/MM/yyyy').format(date);
String _safe(String value) {
  final trim = value.trimLeft();
  return trim.startsWith('=') || trim.startsWith('+') ||
      trim.startsWith('-') || trim.startsWith('@') ? "'" + value : value;
}

List<List<dynamic>> _summary(FinanceReportSection s) => [
  ['Saldo Awal (Bawaan)', s.opening],
  ['Pemasukan Umum', s.otherIncomeTotal],
  ['Perpuluhan (Bagian Pemasukan)', s.titheTotal],
  ['TOTAL PEMASUKAN', s.income],
  ['TOTAL PENGELUARAN', s.expense],
  ['SURPLUS / DEFISIT', s.net],
  ['SALDO AKHIR', s.closing],
];

void _addTitheCsv(List<List<dynamic>> rows, FinanceReportSection s) {
  rows.add(['TABEL PERPULUHAN PER PENYETOR']);
  rows.add(['Nama Jemaat', 'Jumlah Setoran', 'Total Perpuluhan']);
  for (final p in s.titheByPerson) {
    rows.add([_safe(p.name), p.count, p.total]);
  }
  rows.add(['TOTAL PERPULUHAN', s.tithes.length, s.titheTotal]);
}

String financeCompleteCsv(FinanceCompleteReport r) {
  final rows = <List<dynamic>>[
    ['LAPORAN KEUANGAN LENGKAP', _safe(r.churchName)],
    ['Tahun', r.year],
    ['Periode', r.period.name],
    ['Saldo Awal Terverifikasi di Data', r.hasOpening ? 'Ada' : 'Belum'],
    ['Transaksi Tidak Valid', r.invalidRows],
  ];
  for (final w in r.warnings) rows.add(['PERINGATAN', _safe(w)]);
  for (final s in r.sections) {
    rows.add([]);
    rows.add(['PERIODE', s.title]);
    rows.addAll(_summary(s));
    rows.add([]);
    rows.add(['PEMASUKAN UMUM - TANPA PERPULUHAN']);
    rows.add(['Tanggal', 'Keterangan', 'Jumlah']);
    for (final e in s.otherIncome) {
      rows.add([_date(e.date), _safe(e.description), e.amount]);
    }
    rows.add(['TOTAL PEMASUKAN UMUM', '', s.otherIncomeTotal]);
    rows.add([]);
    rows.add(['PENGELUARAN']);
    rows.add(['Tanggal', 'Keterangan', 'Jumlah']);
    for (final e in s.expenses) {
      rows.add([_date(e.date), _safe(e.description), e.amount]);
    }
    rows.add(['TOTAL PENGELUARAN', '', s.expense]);
    rows.add([]);
    _addTitheCsv(rows, s);
  }
  if (r.period == FinanceExportPeriod.allMonths && r.annual != null) {
    rows.add([]);
    rows.add(['REKAP TOTAL TAHUN', r.year]);
    rows.addAll(_summary(r.annual!));
    rows.add([]);
    rows.add(['PERPULUHAN GABUNGAN SETAHUN']);
    _addTitheCsv(rows, r.annual!);
  }
  rows.add([]);
  rows.add(['CATATAN', 'Saldo bawaan tidak menjadi pemasukan. '
      'Perpuluhan sudah termasuk sekali dalam total pemasukan.']);
  return const ListToCsvConverter().convert(rows);
}

pw.Widget _moneyRow(String name, int amount) => pw.Row(
  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  children: [
    pw.Text(name, style: const pw.TextStyle(fontSize: 9)),
    pw.Text(_money(amount), style:
        pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
  ],
);

pw.Widget _table(List<String> headers, List<List<String>> data) =>
    pw.TableHelper.fromTextArray(
      headers: headers,
      data: data.isEmpty
          ? [List<String>.filled(headers.length, '-')] : data,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(
          fontSize: 9, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.all(4),
    );

Future<List<int>> financeCompletePdf(FinanceCompleteReport report) async {
  final doc = pw.Document();
  final parts = <pw.Widget>[
    pw.Text('LAPORAN KEUANGAN LENGKAP',
        style: pw.TextStyle(fontSize: 17,
            fontWeight: pw.FontWeight.bold)),
    pw.Text(report.churchName),
    pw.Text('Tahun ' + report.year.toString() +
        ' | ' + report.period.name),
    pw.SizedBox(height: 10),
    if (!report.hasOpening)
      pw.Text('PERINGATAN: saldo pembuka belum diverifikasi.'),
    if (report.invalidRows > 0)
      pw.Text('PERINGATAN: ada ' + report.invalidRows.toString() +
          ' transaksi tidak valid.'),
    for (final w in report.warnings)
      pw.Text('Catatan audit: ' + w,
          style: const pw.TextStyle(fontSize: 8)),
  ];
  for (final s in report.sections) {
    parts.addAll([
      pw.SizedBox(height: 14),
      pw.Header(level: 1, text: s.title),
      _moneyRow('Saldo Awal (Bawaan)', s.opening),
      _moneyRow('Pemasukan Umum', s.otherIncomeTotal),
      _moneyRow('Perpuluhan (masuk total pemasukan)', s.titheTotal),
      _moneyRow('TOTAL PEMASUKAN', s.income),
      _moneyRow('TOTAL PENGELUARAN', s.expense),
      _moneyRow('SURPLUS / DEFISIT', s.net),
      _moneyRow('SALDO AKHIR', s.closing),
      pw.SizedBox(height: 10),
      pw.Text('Rincian Pemasukan (tanpa perpuluhan)',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      _table(['Tanggal', 'Keterangan', 'Jumlah'],
        s.otherIncome.map((e) => [
          _date(e.date), e.description, _money(e.amount)]).toList()),
      pw.SizedBox(height: 9),
      pw.Text('Rincian Pengeluaran',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      _table(['Tanggal', 'Keterangan', 'Jumlah'],
        s.expenses.map((e) => [
          _date(e.date), e.description, _money(e.amount)]).toList()),
      pw.SizedBox(height: 9),
      pw.Text('Tabel Perpuluhan per Penyetor',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      _table(['Nama Jemaat', 'Jumlah Setoran', 'Total'],
        s.titheByPerson.map((p) => [
          p.name, p.count.toString(), _money(p.total)]).toList()),
      _moneyRow('TOTAL PERPULUHAN', s.titheTotal),
    ]);
  }
  if (report.period == FinanceExportPeriod.allMonths &&
      report.annual != null) {
    parts.addAll([
      pw.SizedBox(height: 12),
      pw.Header(level: 1, text: 'REKAP TAHUN ' +
          report.year.toString()),
      for (final row in _summary(report.annual!))
        _moneyRow(row[0] as String, row[1] as int),
      pw.SizedBox(height: 10),
      pw.Text('Tabel Perpuluhan Tahunan',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      _table(['Nama Jemaat', 'Setoran', 'Total'],
        report.annual!.titheByPerson.map((p) => [
          p.name, p.count.toString(), _money(p.total)]).toList()),
    ]);
  }
  parts.addAll([
    pw.SizedBox(height: 12),
    pw.Text('Catatan: Saldo bawaan bukan pemasukan baru. Total '
        'perpuluhan telah termasuk dalam pemasukan dan tidak dihitung dua kali.',
        style: const pw.TextStyle(fontSize: 8)),
    pw.Text('Cocokkan saldo pembuka dan transaksi dengan buku kas '
        'bendahara sebelum dijadikan laporan resmi.',
        style: const pw.TextStyle(fontSize: 8)),
  ]);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    maxPages: 200,
    build: (context) => parts,
    footer: (context) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Halaman ' + context.pageNumber.toString() +
          '/' + context.pagesCount.toString(),
          style: const pw.TextStyle(fontSize: 8)),
    ),
  ));
  return doc.save();
}
