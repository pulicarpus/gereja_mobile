import 'package:flutter_test/flutter_test.dart';
import '../lib/finance_running_balance.dart';
import '../lib/finance_full_export.dart';

CashLedgerEntry row(int y, int m, int d, int amount, String note,
    {bool income = true, bool tithe = false, String? giver,
    String? giverId, bool opening = false}) => CashLedgerEntry(
  date: DateTime(y, m, d), description: note,
  amount: amount, income: income, isTithe: tithe,
  giverName: giver, giverId: giverId, isOpeningBalance: opening,
);

void main() {
  final entries = <CashLedgerEntry>[
    row(2026, 8, 1, 1000, 'Saldo Pembuka Resmi',
        income: false, opening: true),
    row(2026, 8, 5, 500, 'Kolekte'),
    row(2026, 8, 6, 100, 'Perpuluhan', tithe: true,
        giver: 'Jemaat A', giverId: 'ja'),
    row(2026, 8, 10, 200, 'Perpuluhan', tithe: true,
        giver: 'Jemaat A', giverId: 'ja'),
    row(2026, 8, 20, 700, 'Operasional', income: false),
    row(2026, 9, 1, 1100, 'Saldo Awal September 2026'),
    row(2026, 9, 3, 250, 'Kolekte'),
    row(2026, 9, 4, 50, 'Perpuluhan', tithe: true,
        giver: 'Jemaat B', giverId: 'jb'),
    row(2026, 9, 8, 600, 'Transportasi', income: false),
  ];
  late CashAuditResult audit;
  setUp(() {
    audit = calculateCashRunningBalance(
      entries, selectedYear: 2026, asOf: DateTime(2026, 9, 30));
  });

  test('One month: monthly original transactions and independent tithe', () {
    final r = createFinanceCompleteReport(
      churchName: 'GKII Contoh', year: 2026, month: 8,
      period: FinanceExportPeriod.oneMonth,
      audit: audit, entries: entries);
    expect(r.sections.length, 1);
    final s = r.sections.single;
    expect(s.opening, 1000);
    expect(s.otherIncomeTotal, 500);
    expect(s.titheTotal, 300);
    expect(s.income, 800);
    expect(s.expense, 700);
    expect(s.net, 100);
    expect(s.closing, 1100);
    expect(s.otherIncome.length, 1);
    expect(s.expenses.length, 1);
    expect(s.titheByPerson.length, 1);
    expect(s.titheByPerson.single.name, 'Jemaat A');
    expect(s.titheByPerson.single.count, 2);
    expect(s.titheByPerson.single.total, 300);
    final csv = financeCompleteCsv(r);
    expect(csv, contains('TABEL PERPULUHAN PER PENYETOR'));
    expect(csv, contains('Jemaat A,2,300'));
    expect(csv, isNot(contains('Saldo Awal September 2026')));
  });

  test('All months: monthly sections and consolidated annual rollup', () {
    final r = createFinanceCompleteReport(
      churchName: 'GKII Contoh', year: 2026, month: 9,
      period: FinanceExportPeriod.allMonths,
      audit: audit, entries: entries);
    expect(r.sections.length, 2);
    expect(r.sections.first.closing, 1100);
    expect(r.sections.last.opening, 1100);
    expect(r.sections.last.income, 300);
    expect(r.sections.last.expense, 600);
    expect(r.sections.last.net, -300);
    expect(r.sections.last.closing, 800);
    expect(r.annual!.otherIncomeTotal, 750);
    expect(r.annual!.titheTotal, 350);
    expect(r.annual!.income, 1100);
    expect(r.annual!.expense, 1300);
    expect(r.annual!.net, -200);
    expect(r.annual!.closing, 800);
    final csv = financeCompleteCsv(r);
    expect(csv, contains('REKAP TOTAL TAHUN,2026'));
    expect('TABEL PERPULUHAN PER PENYETOR'.allMatches(csv).length, 1);
    expect(csv, contains('Jemaat B,1,50'));
  });

  test('Annual report: one combined section, no duplicated carry', () {
    final r = createFinanceCompleteReport(
      churchName: 'GKII Contoh', year: 2026, month: 9,
      period: FinanceExportPeriod.oneYear,
      audit: audit, entries: entries);
    expect(r.sections.length, 1);
    expect(r.sections.single.income, 1100);
    expect(r.sections.single.expense, 1300);
    expect(r.sections.single.closing, 800);
    expect(r.sections.single.titheByPerson.length, 2);
    expect(r.sections.single.otherIncome.length, 2);
  });

  test('PDF exports each financial table', () async {
    final r = createFinanceCompleteReport(
      churchName: 'GKII Contoh', year: 2026, month: 9,
      period: FinanceExportPeriod.oneYear,
      audit: audit, entries: entries);
    final bytes = await financeCompletePdf(r);
    expect(bytes.length, greaterThan(1000));
    expect(bytes.sublist(0, 4), [37, 80, 68, 70]); // %PDF
  });
}
