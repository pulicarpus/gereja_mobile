/// Pure, read-only cash ledger calculation. Does not write Firestore documents.
///
/// "Saldo Awal <nama bulan>" is classified as a legacy carried balance, not
/// real new income. The first month can anchor the opening balance if the
/// carry appears exactly once on day 1. Later carries are reconciled against
/// the previously calculated closing balance, never added again.
class CashLedgerEntry {
  final DateTime date;
  final String description;
  final bool income;
  final int amount;
  final bool isTithe;
  const CashLedgerEntry({
    required this.date, required this.description,
    required this.income, required this.amount, this.isTithe = false,
  });
}

class CashMonthBalance {
  final int year, month, opening, income, expense, manualCarry;
  final int manualCarryCount;
  const CashMonthBalance({
    required this.year, required this.month, required this.opening,
    required this.income, required this.expense, required this.manualCarry,
    required this.manualCarryCount,
  });
  int get net => income - expense;
  int get closing => opening + net;
  int get manualDifference => manualCarry - opening;
}

class CashAuditResult {
  final List<CashMonthBalance> months;
  final bool hasDocumentedOpening;
  final List<String> warnings;
  const CashAuditResult(this.months, this.hasDocumentedOpening, this.warnings);
}

const _monthNames = [
  'januari', 'februari', 'maret', 'april', 'mei', 'juni',
  'juli', 'agustus', 'september', 'oktober', 'november', 'desember',
];

final RegExp _legacyOpeningPattern = RegExp(
  r'^\s*saldo\s+awal\s+(januari|februari|maret|april|mei|juni|juli|agustus|september|oktober|november|desember)\b',
  caseSensitive: false,
);

/// Identifies only a monthly opening that matches its transaction month.
/// Unrelated income with the word "saldo" is never automatically excluded.
bool isLegacyCashOpening(CashLedgerEntry entry) {
  if (!entry.income || entry.isTithe) return false;
  final match = _legacyOpeningPattern.firstMatch(entry.description);
  if (match == null) return false;
  return _monthNames.indexOf(match.group(1)!.toLowerCase()) + 1 ==
      entry.date.month;
}

int _monthIndex(DateTime date) => date.year * 12 + date.month;

/// Calculate carry-forward from the oldest available dated record to year-end
/// or asOf. All entries must already be filtered to the selected church and
/// category by the caller. A missing initial opening is explicitly flagged.
CashAuditResult calculateCashRunningBalance(
  Iterable<CashLedgerEntry> values, {
  required int selectedYear,
  DateTime? asOf,
}) {
  final today = asOf ?? DateTime.now();
  final endMonth = selectedYear == today.year
      ? today.month
      : (selectedYear > today.year ? 0 : 12);
  if (endMonth == 0) return const CashAuditResult([], false, [
    'Tahun yang dipilih berada di masa depan.',
  ]);
  final endIndex = selectedYear * 12 + endMonth;
  final records = values.where((e) =>
    e.date.year >= 2020 && e.amount >= 0 &&
    _monthIndex(e.date) <= endIndex).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  if (records.isEmpty) {
    return const CashAuditResult([], false, [
      'Belum ada transaksi untuk dihitung.',
    ]);
  }
  final firstIndex = _monthIndex(records.first.date);
  final groups = <int, List<CashLedgerEntry>>{};
  for (final record in records) {
    groups.putIfAbsent(_monthIndex(record.date), () => []).add(record);
  }
  final firstRecords = groups[firstIndex]!;
  final firstCarries = firstRecords.where(isLegacyCashOpening).toList();
  final documented = firstCarries.length == 1 &&
      firstCarries.first.date.day == 1;
  var openingBalance = documented ? firstCarries.first.amount : 0;
  final warnings = <String>[];
  if (!documented) {
    warnings.add('Saldo awal bulan pertama tidak dapat diverifikasi dari '
        'satu entri Saldo Awal tanggal 1. Asumsi sementara: Rp0.');
  }
  final months = <CashMonthBalance>[];
  for (var index = firstIndex; index <= endIndex; index++) {
    final month = (index - 1) % 12 + 1;
    final year = (index - month) ~/ 12;
    final group = groups[index] ?? const <CashLedgerEntry>[];
    final carryEntries = group.where(isLegacyCashOpening).toList();
    final manualCarry = carryEntries.fold<int>(
        0, (sum, item) => sum + item.amount);
    final monthIncome = group.where(
      (e) => e.income && !isLegacyCashOpening(e),
    ).fold<int>(0, (sum, item) => sum + item.amount);
    final monthExpense = group.where(
      (e) => !e.income,
    ).fold<int>(0, (sum, item) => sum + item.amount);
    if (carryEntries.length > 1) {
      warnings.add('Ada lebih dari satu saldo awal manual pada '
          + month.toString() + '/' + year.toString() + '.');
    }
    if (carryEntries.isNotEmpty && manualCarry != openingBalance) {
      warnings.add('Selisih saldo awal manual pada '
          + month.toString() + '/' + year.toString() + '.');
    }
    final result = CashMonthBalance(
      year: year, month: month, opening: openingBalance,
      income: monthIncome, expense: monthExpense,
      manualCarry: manualCarry,
      manualCarryCount: carryEntries.length,
    );
    months.add(result);
    openingBalance = result.closing;
    if (openingBalance < 0) {
      warnings.add('Saldo kas negatif pada ' + month.toString() +
          '/' + year.toString() + '; periksa transaksi atau sumber dana.');
    }
  }
  return CashAuditResult(months, documented, warnings);
}

/// Rekap tahunan dari bulan yang sudah dihitung dengan saldo berjalan.
/// Opening mencakup saldo pembuka periode (awal tahun atau bulan pertama
/// pembukuan yang tersedia), closing adalah saldo akhir bulan terakhir.
class CashYearSummary {
  final int year;
  final int firstMonth;
  final int lastMonth;
  final int opening;
  final int income;
  final int expense;
  final int closing;
  const CashYearSummary({
    required this.year, required this.firstMonth, required this.lastMonth,
    required this.opening, required this.income, required this.expense,
    required this.closing,
  });
  int get net => income - expense;
}

CashYearSummary? summarizeCashYear(CashAuditResult audit, int year) {
  final months = audit.months.where((m) => m.year == year).toList();
  if (months.isEmpty) return null;
  return CashYearSummary(
    year: year,
    firstMonth: months.first.month,
    lastMonth: months.last.month,
    opening: months.first.opening,
    income: months.fold<int>(0, (value, m) => value + m.income),
    expense: months.fold<int>(0, (value, m) => value + m.expense),
    closing: months.last.closing,
  );
}

