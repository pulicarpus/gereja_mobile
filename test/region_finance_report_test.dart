import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/region_finance_report.dart';
import '../lib/keuangan_daerah_page.dart';
import '../lib/user_manager.dart';

void main() {
  Map<String, dynamic> cash(int year, int month, num amount, String kind) => {
    'tanggal': Timestamp.fromDate(DateTime(year, month, 15)),
    'nominal': amount,
    'jenis': kind,
  };
  test(
    'Monthly finances separate years and expenses and reject malformed money',
    () {
      final report = RegionFinanceYear([
        cash(2026, 1, 100, 'Pemasukan'),
        cash(2026, 1, 40, 'Pengeluaran'),
        cash(2026, 12, 50, 'Pemasukan'),
        cash(2025, 1, 900, 'Pemasukan'),
        cash(2026, 1, -10, 'Pemasukan'),
        cash(2026, 1, double.nan, 'Pemasukan'),
        cash(2026, 1, 50, 'Unknown'),
        {'nominal': 60},
      ], 2026);
      expect(report.totalIncome, 150);
      expect(report.totalExpense, 40);
      expect(report.income[0] - report.expense[0], 60);
      expect(report.income[11], 50);
      expect(report.income[1], 0);
      expect(report.skipped, 4);
      final tithe = RegionFinanceYear(
        [
          {
            'tanggal': Timestamp.fromDate(DateTime(2026, 1, 15)),
            'nominal': 100,
            'tipe': 'Gereja Lokal',
          },
          {
            'tanggal': Timestamp.fromDate(DateTime(2026, 2, 15)),
            'nominal': 20,
            'tipe': 'Pengerja',
          },
        ],
        2026,
        tithe: true,
      );
      expect(tithe.totalIncome, 120);
      expect(tithe.totalExpense, 0);
      expect(tithe.income[0], 100);
    },
  );

  testWidgets(
    'Regional reports expose both charts and monthly tithe details to read-only pastors',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final user = UserManager();
      await user.setUser(
        role: 'admin',
        churchId: 'a',
        churchName: 'A',
        uId: 'pastor',
        uNama: 'Gembala',
        uIsPastor: true,
        uJemaatId: 'p',
        uDaerah: 'Belitang',
      );
      final db = FakeFirebaseFirestore();
      final now = DateTime.now();
      await db.doc('keuangan_daerah/income').set({
        ...cash(now.year, now.month, 100000, 'Pemasukan'),
        'daerah': 'Belitang',
      });
      await db.doc('keuangan_daerah/expense').set({
        ...cash(now.year, now.month, 20000, 'Pengeluaran'),
        'daerah': 'Belitang',
      });
      await db.doc('keuangan_daerah/other').set({
        ...cash(now.year, now.month, 999999, 'Pemasukan'),
        'daerah': 'Ketungau',
      });
      for (var i = 0; i < 2; i++) {
        await db.doc('perpuluhan_daerah/$i').set({
          ...cash(now.year, now.month, 25000, 'Pemasukan'),
          'daerah': 'Belitang',
          'nama': 'GKII Contoh',
          'tipe': 'Gereja Lokal',
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          home: KeuanganDaerahPage(namaDaerah: 'Belitang', firestore: db),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Grafik Bulanan'), findsOneWidget);
      expect(find.text(financeRupiah(80000)), findsWidgets);
      expect(find.text(financeRupiah(999999)), findsNothing);
      expect(find.text('Pemasukan'), findsWidgets);
      // The regional authorization, rather than the church admin role, controls edits.
      expect(find.byIcon(Icons.add_circle), findsNothing);
      await tester.tap(find.text('PERPULUHAN'));
      await tester.pumpAndSettle();
      expect(find.text('Grafik Perpuluhan Bulanan'), findsOneWidget);
      expect(find.text(financeRupiah(50000)), findsWidgets);
      expect(find.text('Input Perpuluhan'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Rekap Perpuluhan per Penyetor'),
        250,
        scrollable:
            find
                .descendant(
                  of: find.byKey(const ValueKey('regional-tithe-report')),
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('GKII Contoh').first);
      await tester.tap(find.text('GKII Contoh').first);
      await tester.pumpAndSettle();
      expect(find.text(financeRupiah(25000)), findsWidgets);
      expect(find.byTooltip('Tindakan setoran'), findsNothing);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await user.reset();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Tithe input offers all registered local churches and multiple pastors without typing',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final user = UserManager();
      await user.setUser(
        role: 'superadmin',
        churchId: 'a',
        churchName: 'A',
        uId: 'admin',
        uNama: 'Admin',
      );
      final db = FakeFirebaseFirestore();
      await db.doc('churches/a').set({
        'daerah': ' BELITANG ',
        'namaGereja': 'GKII Aktif',
        'namaGembala': 'Nama Lama Jangan Dipakai',
        'gembalaProfiles': [
          {'id': 'p1', 'name': 'Pdt Pertama'},
          {'id': 'p2', 'name': 'Pdt Kedua'},
        ],
      });
      await db.doc('churches/b').set({
        'daerah': 'Belitang',
        'namaGereja': 'GKII Lama',
        'namaGembala': 'Pdt Legacy',
      });
      await db.doc('churches/archived').set({
        'daerah': 'Belitang',
        'namaGereja': 'GKII Arsip',
        'namaGembala': 'Pdt Arsip',
        'isArchived': true,
      });
      await db.doc('churches/other').set({
        'daerah': 'Ketungau',
        'namaGereja': 'GKII Luar',
        'namaGembala': 'Pdt Luar',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: KeuanganDaerahPage(namaDaerah: 'Belitang', firestore: db),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('PERPULUHAN'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Input Perpuluhan'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('source-Gereja Lokal')));
      await tester.pumpAndSettle();
      expect(find.text('GKII Aktif'), findsWidgets);
      expect(find.text('GKII Lama'), findsWidgets);
      expect(find.text('GKII Luar'), findsNothing);
      expect(find.text('GKII Arsip'), findsNothing);
      await tester.tap(find.text('GKII Aktif').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gereja Lokal').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pengerja (Hamba Tuhan)').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('source-Pengerja (Hamba Tuhan)')),
      );
      await tester.pumpAndSettle();
      for (final name in ['Pdt Pertama', 'Pdt Kedua', 'Pdt Legacy']) {
        expect(find.text(name), findsWidgets);
      }
      for (final name in [
        'Pdt Luar',
        'Pdt Arsip',
        'Nama Lama Jangan Dipakai',
      ]) {
        expect(find.text(name), findsNothing);
      }
      await tester.tap(find.text('Pdt Kedua').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pengerja (Hamba Tuhan)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Donatur Lain').last);
      await tester.pumpAndSettle();
      final donor = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Nama donatur',
      );
      expect(tester.widget<TextField>(donor).controller!.text, isEmpty);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      expect((await db.collection('perpuluhan_daerah').get()).docs, isEmpty);
      expect((await db.collection('keuangan_daerah').get()).docs, isEmpty);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await user.reset();
      expect(tester.takeException(), isNull);
    },
  );
}
