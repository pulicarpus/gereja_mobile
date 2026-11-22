import 'package:flutter_test/flutter_test.dart';
import '../lib/finance_running_balance.dart';

CashLedgerEntry income(int year, int month, int day, int amount,
    [String description = 'Persembahan']) => CashLedgerEntry(
  date: DateTime(year, month, day), description: description,
  income: true, amount: amount,
);
CashLedgerEntry expense(int year, int month, int day, int amount) =>
    CashLedgerEntry(date: DateTime(year, month, day),
        description: 'Biaya operasional', income: false, amount: amount);

void main() {
  test('Legacy carried balances are not duplicated in income', () {
    final result = calculateCashRunningBalance([
      income(2026, 8, 1, 1000, 'Saldo Awal Agustus 2026'),
      income(2026, 8, 12, 250),
      expense(2026, 8, 14, 100),
      income(2026, 9, 1, 1150, 'Saldo Awal September 2026'),
      income(2026, 9, 2, 80),
      expense(2026, 9, 3, 150),
      income(2026, 10, 1, 1080, 'Saldo Awal Oktober 2026'),
      income(2026, 10, 4, 20),
    ], selectedYear: 2026, asOf: DateTime(2026, 10, 31));
    expect(result.hasDocumentedOpening, true);
    expect(result.warnings, isEmpty);
    expect(result.months.map((m) => m.closing), [1150, 1080, 1100]);
    expect(result.months.map((m) => m.income), [250, 80, 20]);
    expect(result.months.map((m) => m.manualDifference), [0, 0, 0]);
  });

  test('Deficits reduce next opening, not an extra expense', () {
    final result = calculateCashRunningBalance([
      income(2026, 11, 1, 200, 'Saldo Awal November 2026/2027'),
      expense(2026, 11, 5, 350),
      income(2026, 12, 1, 0, 'Saldo Awal Desember 2026'),
      income(2026, 12, 7, 300),
    ], selectedYear: 2026, asOf: DateTime(2026, 12, 20));
    expect(result.months[0].closing, -150);
    expect(result.months[1].opening, -150);
    expect(result.months[1].closing, 150);
    expect(result.months[1].manualDifference, 150);
    expect(result.warnings, isNotEmpty);
  });

  test('Carry-forward persists across new year', () {
    final result = calculateCashRunningBalance([
      income(2026, 12, 1, 200, 'Saldo Awal Desember 2026'),
      income(2026, 12, 12, 100),
      expense(2026, 12, 13, 50),
      income(2027, 1, 1, 250, 'Saldo Awal Januari 2027'),
      income(2027, 1, 2, 40),
    ], selectedYear: 2027, asOf: DateTime(2027, 1, 30));
    expect(result.months.length, 2);
    expect(result.months.last.opening, 250);
    expect(result.months.last.closing, 290);
    expect(result.months.last.manualDifference, 0);
  });

  test('Missing first opening flagged, no invented verified cash', () {
    final result = calculateCashRunningBalance([
      income(2026, 8, 4, 60),
      expense(2026, 8, 6, 20),
    ], selectedYear: 2026, asOf: DateTime(2026, 8, 31));
    expect(result.hasDocumentedOpening, false);
    expect(result.months.single.closing, 40);
    expect(result.warnings, isNotEmpty);
  });

  test('Ordinary income with word saldo is not reclassified', () {
    expect(isLegacyCashOpening(income(2026, 8, 2, 30,
      'Pengembalian saldo kegiatan')), false);
    expect(isLegacyCashOpening(income(2026, 8, 1, 30,
      'Saldo Awal September 2026')), false);
    expect(isLegacyCashOpening(income(2026, 8, 1, 30,
      'Saldo Awal Agustus 2026')), true);
  });

  test('Laporan bulanan asli, tahunan mengambil saldo bulan terakhir', () {
    final result = calculateCashRunningBalance([
      income(2026, 8, 1, 14853000, 'Saldo Awal Agustus 2026'),
      income(2026, 8, 5, 6744000),
      expense(2026, 8, 15, 10758000),
      income(2026, 9, 1, 10839000, 'Saldo Awal September 2026'),
      income(2026, 9, 5, 5537000),
      expense(2026, 9, 6, 5744000),
      income(2026, 10, 1, 10632000, 'Saldo Awal Oktober 2026'),
      income(2026, 10, 6, 7153000),
      expense(2026, 10, 7, 5611000),
      income(2026, 11, 1, 12174000, 'Saldo Awal November 2026'),
      income(2026, 11, 7, 3467000),
    ], selectedYear: 2026, asOf: DateTime(2026, 11, 22));
    final months = result.months;
    expect(months.map((m) => m.net).toList(), [
      -4014000, -207000, 1542000, 3467000,
    ]);
    expect(months.map((m) => m.closing).toList(), [
      10839000, 10632000, 12174000, 15641000,
    ]);
    expect(months[1].opening, months[0].closing);
    expect(months[2].opening, months[1].closing);
    expect(months[3].opening, months[2].closing);
    expect(result.warnings, isEmpty);
    final annual = summarizeCashYear(result, 2026)!;
    expect(annual.firstMonth, 8);
    expect(annual.lastMonth, 11);
    expect(annual.opening, 14853000);
    expect(annual.income, 22901000);
    expect(annual.expense, 22113000);
    expect(annual.net, 788000);
    expect(annual.closing, 15641000);
    expect(annual.closing, annual.opening + annual.net);
  });

  test('Defisit bulanan mengurangi saldo tahun; tidak diduplikasi', () {
    final result = calculateCashRunningBalance([
      income(2026, 12, 1, 0, 'Saldo Awal Desember 2026'),
      income(2026, 12, 10, 100),
      expense(2026, 12, 11, 300),
      income(2027, 1, 1, 0, 'Saldo Awal Januari 2027'),
      income(2027, 1, 12, 400),
      expense(2027, 1, 17, 100),
    ], selectedYear: 2027, asOf: DateTime(2027, 1, 31));
    final december = result.months.first;
    final january = result.months.last;
    expect(december.net, -200);
    expect(december.closing, -200);
    expect(january.opening, -200);
    expect(january.net, 300);
    expect(january.closing, 100);
    final annual = summarizeCashYear(result, 2027)!;
    expect(annual.opening, -200);
    expect(annual.net, 300);
    expect(annual.closing, 100);
  });

  test('Belum ada laporan tahunan sebelum transaksi pertama', () {
    final result = calculateCashRunningBalance([
      income(2026, 8, 1, 150, 'Saldo Awal Agustus 2026'),
    ], selectedYear: 2026, asOf: DateTime(2026, 8, 31));
    expect(summarizeCashYear(result, 2025), isNull);
  });

  test('Saldo pembuka resmi tidak dianggap pemasukan atau pengeluaran', () {
    final result = calculateCashRunningBalance([
      CashLedgerEntry(
        date: DateTime(2026, 9, 1),
        description: 'Saldo pembuka resmi',
        income: false,
        amount: 3000000,
        isOpeningBalance: true,
      ),
      income(2026, 9, 2, 1000000),
      expense(2026, 9, 3, 500000),
      income(2026, 10, 5, 200000),
    ], selectedYear: 2026, asOf: DateTime(2026, 10, 10));
    expect(result.hasDocumentedOpening, true);
    expect(result.warnings, isEmpty);
    expect(result.months.first.opening, 3000000);
    expect(result.months.first.income, 1000000);
    expect(result.months.first.expense, 500000);
    expect(result.months.first.closing, 3500000);
    expect(result.months.last.opening, 3500000);
    expect(result.months.last.closing, 3700000);
  });

  test('Entri pembuka resmi ganda ditandai agar tidak diduplikasi', () {
    final result = calculateCashRunningBalance([
      CashLedgerEntry(
        date: DateTime(2026, 1, 1), description: 'Saldo pembuka',
        income: false, amount: 500, isOpeningBalance: true,
      ),
      income(2026, 1, 1, 500, 'Saldo Awal Januari 2026'),
    ], selectedYear: 2026, asOf: DateTime(2026, 1, 31));
    expect(result.hasDocumentedOpening, false);
    expect(result.months.first.income, 0);
    expect(result.warnings, isNotEmpty);
  });

}
