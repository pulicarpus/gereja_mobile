import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const financeMonths = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];
const _shortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];
String financeRupiah(int value) => NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
).format(value);

/// Both tabs aggregate their own collection: tithe receipts are already mirrored
/// into cash, so adding the two collections would count the same income twice.
class RegionFinanceYear {
  final int year;
  final bool tithe;
  final income = List<int>.filled(12, 0);
  final expense = List<int>.filled(12, 0);
  int skipped = 0;
  RegionFinanceYear(
    Iterable<Map<String, dynamic>> records,
    this.year, {
    this.tithe = false,
  }) {
    for (final data in records) {
      final date = data['tanggal'];
      final amount = data['nominal'];
      if (date is! Timestamp ||
          amount is! num ||
          !amount.isFinite ||
          amount < 0 ||
          (!tithe && !['Pemasukan', 'Pengeluaran'].contains(data['jenis']))) {
        skipped++;
        continue;
      }
      final day = date.toDate();
      if (day.year != year) continue;
      final totals = tithe || data['jenis'] == 'Pemasukan' ? income : expense;
      totals[day.month - 1] += amount.toInt();
    }
  }
  int get totalIncome => income.fold(0, (a, b) => a + b);
  int get totalExpense => expense.fold(0, (a, b) => a + b);
}

class RegionFinanceReport extends StatelessWidget {
  final RegionFinanceYear report;
  final int month;
  final ValueChanged<int> onMonthChanged;
  const RegionFinanceReport({
    super.key,
    required this.report,
    required this.month,
    required this.onMonthChanged,
  });

  Widget _amount(String label, int value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            financeRupiah(value),
            textAlign: TextAlign.end,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
  Widget _card(List<Widget> children) => Card(
    color: Colors.white,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final tithe = report.tithe;
    final maximum = [
      ...report.income,
      ...report.expense,
    ].fold<int>(0, (a, b) => a > b ? a : b);
    final scale = maximum > 0 ? maximum.toDouble() : 10000.0;
    final primary = tithe ? Colors.purple : Colors.green;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card([
          Text(
            tithe
                ? 'Total Perpuluhan Tahun ${report.year}'
                : 'Surplus / Defisit Tahun ${report.year}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              financeRupiah(report.totalIncome - report.totalExpense),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
          const Divider(height: 30),
          _amount(
            tithe ? 'Perpuluhan diterima' : 'Pemasukan',
            report.totalIncome,
            primary,
          ),
          if (!tithe) _amount('Pengeluaran', report.totalExpense, Colors.red),
        ]),
        const SizedBox(height: 24),
        Text(
          tithe ? 'Grafik Perpuluhan Bulanan' : 'Grafik Bulanan',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 18,
          children: [
            Text(
              tithe ? '● Perpuluhan' : '● Pemasukan',
              style: TextStyle(color: primary),
            ),
            if (!tithe)
              const Text('● Pengeluaran', style: TextStyle(color: Colors.red)),
          ],
        ),
        const SizedBox(height: 16),
        // A minimum width keeps twelve month labels readable on narrow phones.
        SizedBox(
          height: 250,
          child: LayoutBuilder(
            builder:
                (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width:
                        constraints.maxWidth < 520 ? 520 : constraints.maxWidth,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: scale * 1.2,
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem:
                                (
                                  group,
                                  groupIndex,
                                  rod,
                                  rodIndex,
                                ) => BarTooltipItem(
                                  '${financeMonths[group.x]}\n${rodIndex == 0 ? (tithe ? "Perpuluhan" : "Pemasukan") : "Pengeluaran"}\n${financeRupiah(rod.toY.toInt())}',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                          ),
                          touchCallback: (event, response) {
                            if (event is FlTapUpEvent &&
                                response?.spot != null) {
                              onMonthChanged(
                                response!.spot!.touchedBarGroup.x + 1,
                              );
                            }
                          },
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget:
                                  (value, meta) => Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      _shortMonths[value.toInt().clamp(0, 11)],
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                            ),
                          ),
                        ),
                        gridData: FlGridData(
                          drawVerticalLine: false,
                          horizontalInterval: scale / 4,
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: List.generate(
                          12,
                          (i) => BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: report.income[i].toDouble(),
                                color: primary,
                                width: 10,
                              ),
                              if (!tithe)
                                BarChartRodData(
                                  toY: report.expense[i].toDouble(),
                                  color: Colors.red,
                                  width: 10,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Rincian Laporan Bulanan',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _card([
          Text(
            '${financeMonths[month - 1]} ${report.year}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Divider(height: 24),
          _amount(
            tithe ? 'Total perpuluhan' : 'Pemasukan',
            report.income[month - 1],
            primary,
          ),
          if (!tithe) ...[
            _amount('Pengeluaran', report.expense[month - 1], Colors.red),
            const Divider(),
            _amount(
              'Arus bersih bulan',
              report.income[month - 1] - report.expense[month - 1],
              Colors.indigo,
            ),
          ],
        ]),
        const SizedBox(height: 12),
        Card(
          color: Colors.white,
          margin: EdgeInsets.zero,
          child: ExpansionTile(
            title: const Text('Rekap Januari–Desember'),
            subtitle: const Text('Ketuk bulan untuk melihat rincian'),
            children: [
              for (var i = 0; i < 12; i++)
                ListTile(
                  selected: month == i + 1,
                  selectedTileColor: Colors.indigo.shade50,
                  title: Text(financeMonths[i]),
                  subtitle: Text(
                    tithe
                        ? 'Perpuluhan: ${financeRupiah(report.income[i])}'
                        : 'Masuk: ${financeRupiah(report.income[i])}\nKeluar: ${financeRupiah(report.expense[i])}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onMonthChanged(i + 1),
                ),
            ],
          ),
        ),
        if (report.skipped > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${report.skipped} catatan tidak dihitung karena tanggal, nominal, atau jenis transaksi tidak valid.',
              style: const TextStyle(color: Colors.deepOrange),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}
