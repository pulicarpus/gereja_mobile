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
}
