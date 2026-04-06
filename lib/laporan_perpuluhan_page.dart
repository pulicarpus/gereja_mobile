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
import 'rincian_perpuluhan_page.dart'; // Buka komen nanti jika file ini sudah dibuat
import 'tambah_perpuluhan_page.dart'; // Buka komen nanti jika file ini sudah dibuat

// --- DATA CLASS (Pengganti RekapPerpuluhanJemaat.kt) ---
class RekapPerpuluhanJemaat {
  final String jemaatId;
  final String namaJemaat;
  int totalPerpuluhan;

  RekapPerpuluhanJemaat({
    required this.jemaatId,
    required this.namaJemaat,
    this.totalPerpuluhan = 0,
  });
}

class LaporanPerpuluhanPage extends StatefulWidget {
  const LaporanPerpuluhanPage({super.key});

  @override
  State<LaporanPerpuluhanPage> createState() => _LaporanPerpuluhanPageState();
}

class _LaporanPerpuluhanPageState extends State<LaporanPerpuluhanPage> {
  final _db = FirebaseFirestore.instance;
  
  List<RekapPerpuluhanJemaat> _rekapList = [];
  RekapPerpuluhanJemaat? _selectedRekap;
  int _grandTotal = 0;
  bool _isLoading = false;

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
    _selectedMonth = now.month - 1; // 0-based index untuk array
    _selectedYear = now.year;
    
    // Generate tahun dari 2020 sampai sekarang (seperti logika Kotlin Bos)
    _tahunArray = List.generate(now.year - 2020 + 1, (index) => now.year - index);
    
    _loadData();
  }

  // --- LOGIKA LOAD & GROUPING DATA ---
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _selectedRekap = null; // Reset pilihan
    });

    String? churchId = UserManager().activeChurchId;
    if (churchId == null) {
      _showSnack("ID Gereja tidak valid.");
      setState(() => _isLoading = false);
      return;
    }

    // Hitung range tanggal bulan terpilih
    DateTime startDate = DateTime(_selectedYear, _selectedMonth + 1, 1);
    // Tanggal 0 di bulan berikutnya = Hari terakhir bulan ini
    DateTime endDate = DateTime(_selectedYear, _selectedMonth + 2, 0, 23, 59, 59);

    try {
      var querySnap = await _db.collection("churches").doc(churchId).collection("perpuluhan")
          .where("tanggal", isGreaterThanOrEqualTo: startDate)
          .where("tanggal", isLessThanOrEqualTo: endDate)
          .get();

      Map<String, RekapPerpuluhanJemaat> rekapMap = {};
      int tempGrandTotal = 0;

      for (var doc in querySnap.docs) {
        var data = doc.data();
        int jumlah = (data['jumlah'] ?? 0) as int;
        String jemaatId = data['jemaatId'] ?? "";
        String namaJemaat = data['namaJemaat'] ?? "Tanpa Nama";
        
        // Gunakan jemaatId sebagai key, atau nama jika tidak punya ID
        String key = jemaatId.isNotEmpty ? jemaatId : namaJemaat;

        if (!rekapMap.containsKey(key)) {
          rekapMap[key] = RekapPerpuluhanJemaat(jemaatId: jemaatId, namaJemaat: namaJemaat);
        }
        rekapMap[key]!.totalPerpuluhan += jumlah;
        tempGrandTotal += jumlah;
      }

      var sortedList = rekapMap.values.toList();
      sortedList.sort((a, b) => a.namaJemaat.compareTo(b.namaJemaat));

      setState(() {
        _rekapList = sortedList;
        _grandTotal = tempGrandTotal;
      });
    } catch (e) {
      _showSnack("Gagal memuat data: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String formatRupiah(int amount) {
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- EXPORT PDF ---
  Future<void> _exportToPdf() async {
    if (_rekapList.isEmpty) {
      _showSnack("Tidak ada data untuk diekspor");
      return;
    }
    _showSnack("Sedang membuat PDF...");

    final pdf = pw.Document();
    
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text("Laporan Perpuluhan", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text("Periode: ${_bulanArray[_selectedMonth]} $_selectedYear"),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headers: ['Nama Jemaat', 'Total Perpuluhan'],
                data: _rekapList.map((rekap) => [rekap.namaJemaat, formatRupiah(rekap.totalPerpuluhan)]).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
              ),
              pw.SizedBox(height: 15),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text("Grand Total: ${formatRupiah(_grandTotal)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              )
            ],
          );
        },
      ),
    );

    final dir = await getExternalStorageDirectory();
    final file = File("${dir!.path}/Laporan_Perpuluhan_${DateTime.now().millisecondsSinceEpoch}.pdf");
    await file.writeAsBytes(await pdf.save());
    
    _showSnack("PDF berhasil dibuat!");
    OpenFilex.open(file.path);
  }

  // --- EXPORT CSV ---
  Future<void> _exportToCsv() async {
    if (_rekapList.isEmpty) {
      _showSnack("Tidak ada data untuk diekspor");
      return;
    }
    
    List<List<dynamic>> rows = [];
    rows.add(["Nama Jemaat", "Total Perpuluhan"]); // Header
    
    for (var rekap in _rekapList) {
      rows.add([rekap.namaJemaat, rekap.totalPerpuluhan]);
    }
    rows.add([""]);
    rows.add(["Grand Total", _grandTotal]);

    String csv = const ListToCsvConverter().convert(rows);
    
    final dir = await getExternalStorageDirectory();
    final file = File("${dir!.path}/Laporan_Perpuluhan_${DateTime.now().millisecondsSinceEpoch}.csv");
    await file.writeAsString(csv);

    _showSnack("CSV berhasil dibuat!");
    OpenFilex.open(file.path);
  }

  // --- UI BUILDING ---
  @override
  Widget build(BuildContext context) {
    bool isAdmin = UserManager().isAdmin();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Laporan Perpuluhan"),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        actions: [
          if (isAdmin)
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
          // SPINNER / DROPDOWN FILTER
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _selectedMonth,
                    items: List.generate(12, (index) => DropdownMenuItem(value: index, child: Text(_bulanArray[index]))),
                    onChanged: (val) { if (val != null) { setState(() => _selectedMonth = val); _loadData(); } },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _selectedYear,
                    items: _tahunArray.map((year) => DropdownMenuItem(value: year, child: Text(year.toString()))).toList(),
                    onChanged: (val) { if (val != null) { setState(() => _selectedYear = val); _loadData(); } },
                  ),
                ),
              ],
            ),
          ),
          
          // HEADER TOTAL
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.indigo.shade50,
            child: Column(
              children: [
                Text("Total Perpuluhan (${_bulanArray[_selectedMonth]} $_selectedYear)", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(formatRupiah(_grandTotal), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.indigo)),
              ],
            ),
          ),

          // LIST VIEW (Pengganti Adapter)
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _rekapList.isEmpty
                ? const Center(child: Text("Tidak ada data perpuluhan di bulan ini", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _rekapList.length,
                    itemBuilder: (context, index) {
                      var rekap = _rekapList[index];
                      bool isSelected = _selectedRekap == rekap;
                      
                      return Card(
                        elevation: isSelected ? 4 : 1,
                        color: isSelected ? Colors.indigo.shade100 : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: isSelected ? Colors.indigo : Colors.transparent, width: 2)
                        ),
                        child: ListTile(
                          onTap: () {
                            setState(() => _selectedRekap = isSelected ? null : rekap);
                          },
                          leading: CircleAvatar(
                            backgroundColor: isSelected ? Colors.indigo : Colors.grey[300],
                            child: Icon(Icons.person, color: isSelected ? Colors.white : Colors.grey[600]),
                          ),
                          title: Text(rekap.namaJemaat, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(formatRupiah(rekap.totalPerpuluhan), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                          trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.indigo) : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      
      // BOTTOM NAVIGATION MENU (Khusus Admin)
      bottomNavigationBar: !isAdmin ? null : Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.list_alt),
                label: const Text("Lihat Rincian"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: _selectedRekap == null ? null : () {
                  // Navigator.push(context, MaterialPageRoute(builder: (_) => RincianPerpuluhanPage(
                  //   jemaatId: _selectedRekap!.jemaatId,
                  //   namaJemaat: _selectedRekap!.namaJemaat,
                  //   bulan: _selectedMonth,
                  //   tahun: _selectedYear,
                  // )));
                  _showSnack("Navigasi ke Rincian: ${_selectedRekap!.namaJemaat}");
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text("Catat Baru"),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF075E54), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: () {
                  // Navigator.push(context, MaterialPageRoute(builder: (_) => TambahPerpuluhanPage()));
                  _showSnack("Navigasi ke Tambah Perpuluhan");
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}