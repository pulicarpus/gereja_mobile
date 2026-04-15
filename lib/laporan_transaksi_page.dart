import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:csv/csv.dart';

import 'user_manager.dart';
// 👇 KABEL NAVIGASI SUDAH TERSAMBUNG 👇
import 'tambah_transaksi_page.dart'; 
import 'tambah_perpuluhan_page.dart'; 

// --- DATA CLASS TRANSAKSI GABUNGAN ---
class TransaksiItem {
  final String id;
  final String keterangan;
  final int jumlah;
  final String jenis; // "Pemasukan" atau "Pengeluaran"
  final DateTime tanggal;
  final String sumber; // "transaksi" atau "perpuluhan"
  final String? kategori;

  TransaksiItem({
    required this.id,
    required this.keterangan,
    required this.jumlah,
    required this.jenis,
    required this.tanggal,
    required this.sumber,
    this.kategori,
  });
}

class LaporanTransaksiPage extends StatefulWidget {
  final String? tipeFilter; // "Pemasukan", "Pengeluaran", atau null (Semua)
  final String? filterKategorial; // "Pemuda", "Sekolah Minggu", atau null (Umum)

  const LaporanTransaksiPage({
    super.key,
    this.tipeFilter,
    this.filterKategorial,
  });

  @override
  State<LaporanTransaksiPage> createState() => _LaporanTransaksiPageState();
}

class _LaporanTransaksiPageState extends State<LaporanTransaksiPage> {
  final _db = FirebaseFirestore.instance;
  
  List<TransaksiItem> _transaksiList = [];
  bool _isLoading = false;
  
  int _totalPemasukan = 0;
  int _totalPengeluaran = 0;
  int _totalSaldoTahunan = 0; // 👇 VARIABEL BARU UNTUK KARTU SULTAN 👇

  late int _selectedMonth;
  late int _selectedYear;

  final List<String> _bulanArray = [
    "Januari", "Februari", "Maret", "April", "Mei", "Juni", 
    "Juli", "Agustus", "September", "Oktober", "November", "Desember"
  ];
  List<int> _tahunArray = [];

  @override
  void initState() {
    super.initState();
    DateTime now = DateTime.now();
    _selectedMonth = now.month - 1; 
    _selectedYear = now.year;
    
    _tahunArray = List.generate(now.year - 2020 + 1, (index) => now.year - index);
    
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    String? churchId = UserManager().activeChurchId;
    if (churchId == null) {
      _showSnack("ID Gereja tidak valid.");
      setState(() => _isLoading = false);
      return;
    }

    // Rentang Waktu Bulanan (Untuk List Bawah)
    DateTime startDateBulanan = DateTime(_selectedYear, _selectedMonth + 1, 1);
    DateTime endDateBulanan = DateTime(_selectedYear, _selectedMonth + 2, 0, 23, 59, 59);

    // Rentang Waktu Tahunan (Untuk Kartu Sultan Atas)
    DateTime startDateTahunan = DateTime(_selectedYear, 1, 1);
    DateTime endDateTahunan = DateTime(_selectedYear, 12, 31, 23, 59, 59);

    bool isModeUmum = widget.filterKategorial == null || widget.filterKategorial!.isEmpty;

    try {
      var churchRef = _db.collection("churches").doc(churchId);

      // --- MENGAMBIL DATA UNTUK BULAN INI (Untuk List) ---
      var trxQueryBulanan = churchRef.collection("transaksi")
          .where("tanggal", isGreaterThanOrEqualTo: startDateBulanan)
          .where("tanggal", isLessThanOrEqualTo: endDateBulanan);
          
      if (widget.tipeFilter != null) {
        trxQueryBulanan = trxQueryBulanan.where("jenis", isEqualTo: widget.tipeFilter);
      }

      List<Future<QuerySnapshot<Map<String, dynamic>>>> tasksToRun = [trxQueryBulanan.get()];

      bool fetchPerpuluhan = isModeUmum && (widget.tipeFilter == "Pemasukan" || widget.tipeFilter == null);
      if (fetchPerpuluhan) {
        var perpQueryBulanan = churchRef.collection("perpuluhan")
            .where("tanggal", isGreaterThanOrEqualTo: startDateBulanan)
            .where("tanggal", isLessThanOrEqualTo: endDateBulanan);
        tasksToRun.add(perpQueryBulanan.get());
      }

      // --- MENGAMBIL DATA UNTUK TAHUN INI (Hanya Total Saldo) ---
      var trxQueryTahunan = churchRef.collection("transaksi")
          .where("tanggal", isGreaterThanOrEqualTo: startDateTahunan)
          .where("tanggal", isLessThanOrEqualTo: endDateTahunan);
      tasksToRun.add(trxQueryTahunan.get());

      if (fetchPerpuluhan) {
        var perpQueryTahunan = churchRef.collection("perpuluhan")
            .where("tanggal", isGreaterThanOrEqualTo: startDateTahunan)
            .where("tanggal", isLessThanOrEqualTo: endDateTahunan);
        tasksToRun.add(perpQueryTahunan.get());
      }

      // Eksekusi semua tugas sekaligus
      var results = await Future.wait(tasksToRun);
      
      List<TransaksiItem> combinedList = [];
      int tempMasukBulan = 0;
      int tempKeluarBulan = 0;
      int tempSaldoTahunan = 0;

      // 1. PROSES TRANSAKSI BULANAN (Untuk List)
      for (var doc in results[0].docs) {
        var data = doc.data();
        String kat = (data['kategori'] as String?)?.trim() ?? "";
        
        if (isModeUmum) {
          if (kat.isNotEmpty && kat.toLowerCase() != "umum") continue;
        } else {
          if (kat.toLowerCase() != widget.filterKategorial?.trim().toLowerCase()) continue;
        }

        var trx = TransaksiItem(
          id: doc.id,
          keterangan: data['keterangan'] ?? "Tanpa Keterangan",
          jumlah: (data['jumlah'] ?? 0) as int,
          jenis: data['jenis'] ?? "Pemasukan",
          tanggal: (data['tanggal'] as Timestamp).toDate(),
          sumber: "transaksi",
          kategori: kat,
        );
        
        combinedList.add(trx);
        if (trx.jenis == "Pemasukan") tempMasukBulan += trx.jumlah;
        else tempKeluarBulan += trx.jumlah;
      }

      // 2. PROSES PERPULUHAN BULANAN (Jika Ada)
      int offset = fetchPerpuluhan ? 1 : 0;
      if (fetchPerpuluhan) {
        for (var doc in results[1].docs) {
          var data = doc.data();
          var trx = TransaksiItem(
            id: doc.id,
            keterangan: "Perpuluhan: ${data['namaJemaat'] ?? 'Tanpa Nama'}",
            jumlah: (data['jumlah'] ?? 0) as int,
            jenis: "Pemasukan",
            tanggal: (data['tanggal'] as Timestamp).toDate(),
            sumber: "perpuluhan",
            kategori: "Umum",
          );
          
          combinedList.add(trx);
          tempMasukBulan += trx.jumlah;
        }
      }

      // 3. PROSES TOTAL SALDO TAHUNAN
      var docTahunan = results[1 + offset].docs;
      for (var doc in docTahunan) {
          var data = doc.data();
          String kat = (data['kategori'] as String?)?.trim() ?? "";
          
          if (isModeUmum) {
            if (kat.isNotEmpty && kat.toLowerCase() != "umum") continue;
          } else {
            if (kat.toLowerCase() != widget.filterKategorial?.trim().toLowerCase()) continue;
          }

          int jml = (data['jumlah'] ?? 0) as int;
          String jns = data['jenis'] ?? "Pemasukan";
          
          if (jns == "Pemasukan") tempSaldoTahunan += jml;
          else tempSaldoTahunan -= jml;
      }

      if (fetchPerpuluhan) {
         var docPerpTahunan = results[2 + offset].docs;
         for (var doc in docPerpTahunan) {
            int jml = (doc.data()['jumlah'] ?? 0) as int;
            tempSaldoTahunan += jml;
         }
      }

      combinedList.sort((a, b) => b.tanggal.compareTo(a.tanggal));

      setState(() {
        _transaksiList = combinedList;
        _totalPemasukan = tempMasukBulan;
        _totalPengeluaran = tempKeluarBulan;
        _totalSaldoTahunan = tempSaldoTahunan;
      });

    } catch (e) {
      _showSnack("Gagal memuat: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String formatRupiah(int amount) {
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);
  }

  String formatTanggal(DateTime date) {
    return DateFormat('dd MMM yyyy', 'id_ID').format(date);
  }

  void _showSnack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showOptionsDialog(TransaksiItem trx) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(15),
              child: Text(trx.keterangan, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text("Edit"),
              onTap: () {
                Navigator.pop(context);
                _navigateToEdit(trx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Hapus"),
              onTap: () {
                Navigator.pop(context);
                _showDeleteDialog(trx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEdit(TransaksiItem trx) {
    if (trx.sumber == "perpuluhan") {
      Navigator.push(context, MaterialPageRoute(builder: (_) => TambahPerpuluhanPage(
        perpuluhanEdit: PerpuluhanEditData(
          id: trx.id, 
          jumlah: trx.jumlah, 
          namaJemaat: trx.keterangan.replaceAll("Perpuluhan: ", ""), // Bersihkan prefix
          tanggal: trx.tanggal
        )
      ))).then((_) => _loadData());
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => TambahTransaksiPage(
        transaksiEdit: TransaksiEditData(
          id: trx.id, 
          keterangan: trx.keterangan, 
          jumlah: trx.jumlah, 
          jenis: trx.jenis, 
          tanggal: trx.tanggal,
          kategori: trx.kategori, // Kategori dikirim agar tidak bocor
        ), 
        filterKategorial: widget.filterKategorial,
      ))).then((_) => _loadData());
    }
  }

  void _showDeleteDialog(TransaksiItem trx) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus?"),
        content: Text("Yakin ingin menghapus '${trx.keterangan}'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tidak")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              _deleteTransaksi(trx);
            },
            child: const Text("Ya, Hapus"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTransaksi(TransaksiItem trx) async {
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) return;

    try {
      String collectionName = trx.sumber == "perpuluhan" ? "perpuluhan" : "transaksi";
      await _db.collection("churches").doc(churchId).collection(collectionName).doc(trx.id).delete();
      _showSnack("Berhasil dihapus");
      _loadData();
    } catch (e) {
      _showSnack("Gagal menghapus: $e");
    }
  }

  Future<void> _exportToPdf() async {
    if (_transaksiList.isEmpty) return _showSnack("Data kosong");
    _showSnack("Membuat PDF...");

    final pdf = pw.Document();
    String title = "Laporan ${widget.tipeFilter ?? 'Keuangan'} (${widget.filterKategorial ?? 'Umum'})";

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(child: pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
              pw.Center(child: pw.Text("Periode: ${_bulanArray[_selectedMonth]} $_selectedYear")),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headers: ['Tanggal', 'Keterangan', 'Masuk', 'Keluar'],
                data: _transaksiList.map((t) => [
                  formatTanggal(t.tanggal),
                  t.keterangan,
                  t.jenis == "Pemasukan" ? formatRupiah(t.jumlah) : "-",
                  t.jenis == "Pengeluaran" ? formatRupiah(t.jumlah) : "-"
                ]).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              ),
              pw.SizedBox(height: 15),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (widget.tipeFilter != "Pengeluaran") pw.Text("Total Pemasukan: ${formatRupiah(_totalPemasukan)}"),
                    if (widget.tipeFilter != "Pemasukan") pw.Text("Total Pengeluaran: ${formatRupiah(_totalPengeluaran)}"),
                  ]
                )
              )
            ],
          );
        },
      ),
    );

    final dir = await getExternalStorageDirectory();
    final file = File("${dir!.path}/Laporan_${DateTime.now().millisecondsSinceEpoch}.pdf");
    await file.writeAsBytes(await pdf.save());
    _showSnack("PDF berhasil dibuat!");
    OpenFilex.open(file.path);
  }

  Future<void> _exportToCsv() async {
    if (_transaksiList.isEmpty) return _showSnack("Data kosong");
    
    List<List<dynamic>> rows = [["Tanggal", "Keterangan", "Jenis", "Jumlah"]];
    for (var t in _transaksiList) {
      rows.add([formatTanggal(t.tanggal), t.keterangan, t.jenis, t.jumlah]);
    }
    
    String csv = const ListToCsvConverter().convert(rows);
    final dir = await getExternalStorageDirectory();
    final file = File("${dir!.path}/Laporan_${DateTime.now().millisecondsSinceEpoch}.csv");
    await file.writeAsString(csv);
    _showSnack("CSV berhasil dibuat!");
    OpenFilex.open(file.path);
  }

  @override
  Widget build(BuildContext context) {
    final userManager = UserManager();
    bool isGlobalAdmin = userManager.isAdmin();
    bool isPengurusKomisiIni = false;
    
    if (widget.filterKategorial != null && widget.filterKategorial!.isNotEmpty) {
      isPengurusKomisiIni = userManager.isPengurus && (userManager.userKomisi == widget.filterKategorial);
    }
    
    bool canEdit = isGlobalAdmin || isPengurusKomisiIni;
    String label = widget.filterKategorial == null || widget.filterKategorial!.isEmpty ? "Umum" : widget.filterKategorial!;
    String titleText = "Laporan ${widget.tipeFilter ?? 'Keuangan'} ($label)";

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Ubah background jadi abu-abu bersih
      appBar: AppBar(
        title: Text(titleText, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (canEdit)
            PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'pdf') _exportToPdf();
                if (val == 'csv') _exportToCsv();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'pdf', child: Text("Export ke PDF")),
                const PopupMenuItem(value: 'csv', child: Text("Export ke CSV")),
              ],
            )
        ],
      ),
      body: Column(
        children: [
          // 👇 INI DIA KARTU SULTAN TAMPILAN BARU 👇
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))]
            ),
            child: Column(
              children: [
                // DROPDOWN BULAN & TAHUN
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            isExpanded: true,
                            value: _selectedMonth,
                            items: List.generate(12, (index) => DropdownMenuItem(value: index, child: Text(_bulanArray[index]))),
                            onChanged: (val) { if (val != null) { setState(() => _selectedMonth = val); _loadData(); } },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            isExpanded: true,
                            value: _selectedYear,
                            items: _tahunArray.map((year) => DropdownMenuItem(value: year, child: Text(year.toString()))).toList(),
                            onChanged: (val) { if (val != null) { setState(() => _selectedYear = val); _loadData(); } },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                
                // TOTAL SALDO TAHUNAN
                const Text("Total Saldo Tahun Ini", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(formatRupiah(_totalSaldoTahunan), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.blue)),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 15),
                  child: Divider(),
                ),

                // RINGKASAN PEMASUKAN & PENGELUARAN BULANAN
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Pemasukan Bulan Ini", style: TextStyle(color: Colors.grey, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(formatRupiah(_totalPemasukan), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ),
                    Container(height: 30, width: 1, color: Colors.grey.shade300),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text("Pengeluaran Bulan Ini", style: TextStyle(color: Colors.grey, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(formatRupiah(_totalPengeluaran), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 10),

          // 👇 LIST TRANSAKSI BAWAH 👇
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _transaksiList.isEmpty
                ? const Center(child: Text("Data Kosong", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    itemCount: _transaksiList.length,
                    itemBuilder: (context, index) {
                      var t = _transaksiList[index];
                      bool isMasuk = t.jenis == "Pemasukan";
                      
                      return Card(
                        elevation: 1,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(15),
                          onTap: canEdit ? () => _showOptionsDialog(t) : null,
                          child: Padding(
                            padding: const EdgeInsets.all(15),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: isMasuk ? Colors.green.shade50 : Colors.red.shade50,
                                  child: Icon(
                                    isMasuk ? Icons.arrow_downward : Icons.arrow_upward, 
                                    color: isMasuk ? Colors.green : Colors.red,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(t.keterangan, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                                      const SizedBox(height: 4),
                                      Text(formatTanggal(t.tanggal), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Text(
                                  formatRupiah(t.jumlah),
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isMasuk ? Colors.green : Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      
      floatingActionButton: !canEdit ? null : FloatingActionButton(
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => TambahTransaksiPage(
            filterKategorial: widget.filterKategorial,
          ))).then((_) => _loadData());
        },
      ),
    );
  }
}