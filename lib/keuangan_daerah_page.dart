import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// 👇 MESIN FORMAT TITIK OTOMATIS SAAT MENGETIK RUPIAH 👇
class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    String cleanText = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanText.isEmpty) return const TextEditingValue(text: '');
    final int value = int.parse(cleanText);
    final String formatted = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(value);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class KeuanganDaerahPage extends StatelessWidget {
  final String namaDaerah;

  const KeuanganDaerahPage({super.key, required this.namaDaerah});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text("Keuangan ${namaDaerah.toUpperCase()}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: Colors.orange,
            indicatorWeight: 4,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              Tab(icon: Icon(Icons.account_balance_wallet), text: "KAS OPERASIONAL"),
              Tab(icon: Icon(Icons.volunteer_activism), text: "PERPULUHAN"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _KasDaerahTab(namaDaerah: namaDaerah),
            _PerpuluhanTab(namaDaerah: namaDaerah),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 👇 TAB 1: KAS OPERASIONAL DAERAH 👇
// ============================================================================
class _KasDaerahTab extends StatefulWidget {
  final String namaDaerah;
  const _KasDaerahTab({required this.namaDaerah});

  @override
  State<_KasDaerahTab> createState() => _KasDaerahTabState();
}

class _KasDaerahTabState extends State<_KasDaerahTab> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  List<QueryDocumentSnapshot> _filteredDocs = []; // Untuk simpan data yang akan diexport
  int _blnPemasukan = 0;
  int _blnPengeluaran = 0;

  final List<int> _years = List.generate(5, (index) => DateTime.now().year - index);
  final List<String> _months = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];

  // 👇 FUNGSI EKSPORT PDF KAS OPERASIONAL 👇
  Future<void> _exportToPDF() async {
    if (_filteredDocs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tidak ada data untuk diekspor!")));
      return;
    }

    final pdf = pw.Document();
    final String blnStr = _months[_selectedMonth - 1];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("Laporan Kas Operasional Daerah ${widget.namaDaerah}", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text("Periode: $blnStr $_selectedYear", style: const pw.TextStyle(fontSize: 14)),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headers: ['Tanggal', 'Jenis', 'Keterangan', 'Nominal (Rp)'],
                data: _filteredDocs.map((doc) {
                  var d = doc.data() as Map<String, dynamic>;
                  DateTime dt = (d['tanggal'] as Timestamp).toDate();
                  return [
                    DateFormat('dd MMM yyyy').format(dt),
                    d['jenis'],
                    d['keterangan'],
                    _currencyFormat.format(d['nominal']).replaceAll("Rp ", "")
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
                cellAlignment: pw.Alignment.centerLeft,
              ),
              pw.SizedBox(height: 20),
              pw.Text("Ringkasan Bulan Ini:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text("Total Pemasukan: ${_currencyFormat.format(_blnPemasukan)}", style: const pw.TextStyle(color: PdfColors.green)),
              pw.Text("Total Pengeluaran: ${_currencyFormat.format(_blnPengeluaran)}", style: const pw.TextStyle(color: PdfColors.red)),
              pw.Text("Saldo Bersih: ${_currencyFormat.format(_blnPemasukan - _blnPengeluaran)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          );
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Kas_${widget.namaDaerah}_${blnStr}_$_selectedYear.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: 'Laporan Kas Daerah ${widget.namaDaerah}');
  }

  // 👇 FUNGSI EKSPORT CSV (EXCEL) KAS OPERASIONAL 👇
  Future<void> _exportToCSV() async {
    if (_filteredDocs.isEmpty) return;

    String csvData = "Tanggal,Jenis,Keterangan,Nominal\n";
    for (var doc in _filteredDocs) {
      var d = doc.data() as Map<String, dynamic>;
      DateTime dt = (d['tanggal'] as Timestamp).toDate();
      String tgl = DateFormat('yyyy-MM-dd').format(dt);
      String ket = d['keterangan'].toString().replaceAll('"', '""'); // Escape quotes
      csvData += "$tgl,${d['jenis']},\"$ket\",${d['nominal']}\n";
    }

    final String blnStr = _months[_selectedMonth - 1];
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Kas_${widget.namaDaerah}_${blnStr}_$_selectedYear.csv');
    await file.writeAsString(csvData);
    await Share.shareXFiles([XFile(file.path)], text: 'Data CSV Kas ${widget.namaDaerah}');
  }

  // 👇 TAMPILKAN OPSI EKSPORT 👇
  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            const Padding(
              padding: EdgeInsets.all(16), 
              child: Text("Cetak / Ekspor Laporan", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo))
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text("Ekspor sebagai PDF", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("Format rapi untuk dicetak / dibagikan"),
              onTap: () { Navigator.pop(ctx); _exportToPDF(); },
            ),
            ListTile(
              leading: const Icon(Icons.table_view, color: Colors.green),
              title: const Text("Ekspor sebagai CSV (Excel)", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("Format data mentah untuk diolah di Excel"),
              onTap: () { Navigator.pop(ctx); _exportToCSV(); },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showAddTransactionDialog(bool isPemasukan) => _showTransactionForm(isPemasukan: isPemasukan);

  void _showEditTransactionDialog(String docId, Map<String, dynamic> data) {
    bool isPemasukan = data['jenis'] == "Pemasukan";
    _showTransactionForm(
      isPemasukan: isPemasukan,
      docId: docId,
      initialNominal: data['nominal'].toString(),
      initialKeterangan: data['keterangan'],
      initialDate: (data['tanggal'] as Timestamp?)?.toDate(),
    );
  }

  void _showTransactionForm({required bool isPemasukan, String? docId, String? initialNominal, String? initialKeterangan, DateTime? initialDate}) {
    // 🔥 FORMAT AWAL SAAT EDIT 🔥
    String formattedNominal = "";
    if (initialNominal != null && initialNominal.isNotEmpty) {
      formattedNominal = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(int.parse(initialNominal));
    }

    final etNominal = TextEditingController(text: formattedNominal);
    final etKeterangan = TextEditingController(text: initialKeterangan ?? "");
    String jenis = isPemasukan ? "Pemasukan" : "Pengeluaran";
    DateTime selectedDate = initialDate ?? DateTime.now();

    bool isEdit = docId != null;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(isEdit ? Icons.edit : (isPemasukan ? Icons.south_west : Icons.north_east), color: isEdit ? Colors.blue : (isPemasukan ? Colors.green : Colors.red)),
              const SizedBox(width: 8),
              Text(isEdit ? "Edit $jenis" : "Tambah $jenis", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () async {
                    DateTime? picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (picked != null) setStateDialog(() => selectedDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(5)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(DateFormat('dd MMMM yyyy').format(selectedDate), style: const TextStyle(fontSize: 15)),
                        const Icon(Icons.calendar_month, color: Colors.indigo),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: etNominal,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    CurrencyInputFormatter() // 👈 SISIPKAN FORMATTER TITIK OTOMATIS
                  ],
                  decoration: const InputDecoration(labelText: "Nominal", border: OutlineInputBorder(), prefixText: "Rp "),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: etKeterangan,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: "Keterangan", hintText: "Cth: Konsumsi Rapat", border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Batal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: isEdit ? Colors.blue : (isPemasukan ? Colors.green : Colors.red), foregroundColor: Colors.white),
              onPressed: () async {
                if (etNominal.text.trim().isEmpty || etKeterangan.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠ Mohon isi semua kolom!"), backgroundColor: Colors.orange));
                  return;
                }
                
                int nominal = int.tryParse(etNominal.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                if (nominal <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠ Nominal tidak valid!"), backgroundColor: Colors.orange));
                  return;
                }

                Navigator.pop(dialogContext);

                try {
                  Map<String, dynamic> payload = {
                    "daerah": widget.namaDaerah,
                    "jenis": jenis,
                    "nominal": nominal,
                    "keterangan": etKeterangan.text.trim(),
                    "tanggal": Timestamp.fromDate(selectedDate),
                  };

                  if (isEdit) {
                    await _db.collection("keuangan_daerah").doc(docId).update(payload);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Transaksi berhasil diedit!"), backgroundColor: Colors.blue));
                  } else {
                    await _db.collection("keuangan_daerah").add(payload);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ $jenis berhasil dicatat!"), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Gagal menyimpan: $e"), backgroundColor: Colors.red));
                }
              },
              child: Text(isEdit ? "Simpan Perubahan" : "Simpan"),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptionsBottomSheet(String docId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text("Edit Transaksi", style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () { Navigator.pop(ctx); _showEditTransactionDialog(docId, data); },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Hapus Transaksi", style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () { Navigator.pop(ctx); _showDeleteDialog(docId, data['keterangan']); },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(String docId, String keterangan) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Hapus Transaksi?"),
        content: Text("Yakin ingin menghapus $keterangan?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              WriteBatch batch = _db.batch();
              batch.delete(_db.collection("keuangan_daerah").doc(docId));
              batch.delete(_db.collection("perpuluhan_daerah").doc(docId));
              await batch.commit();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data dihapus")));
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.white)),
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _months[_selectedMonth - 1],
                    decoration: InputDecoration(labelText: "Bulan", contentPadding: const EdgeInsets.symmetric(horizontal: 15), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    items: _months.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14)))).toList(),
                    onChanged: (val) => setState(() => _selectedMonth = _months.indexOf(val!) + 1),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedYear,
                    decoration: InputDecoration(labelText: "Tahun", contentPadding: const EdgeInsets.symmetric(horizontal: 15), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    items: _years.map((e) => DropdownMenuItem(value: e, child: Text(e.toString(), style: const TextStyle(fontSize: 14)))).toList(),
                    onChanged: (val) => setState(() => _selectedYear = val!),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection("keuangan_daerah").where("daerah", isEqualTo: widget.namaDaerah).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                
                var docs = snapshot.data?.docs.toList() ?? [];
                
                docs.sort((a, b) {
                  Timestamp tA = (a.data() as Map<String, dynamic>)['tanggal'] ?? Timestamp.now();
                  Timestamp tB = (b.data() as Map<String, dynamic>)['tanggal'] ?? Timestamp.now();
                  return tB.compareTo(tA); 
                });
                
                int thnPemasukan = 0, thnPengeluaran = 0;
                _blnPemasukan = 0; _blnPengeluaran = 0;
                _filteredDocs = []; // Reset filtered docs

                for (var doc in docs) {
                  var data = doc.data() as Map<String, dynamic>;
                  Timestamp? ts = data['tanggal'] as Timestamp?;
                  if (ts == null) continue;

                  DateTime dt = ts.toDate();
                  int nom = data['nominal'] ?? 0;
                  bool isMasuk = data['jenis'] == "Pemasukan";

                  if (dt.year == _selectedYear) {
                    isMasuk ? thnPemasukan += nom : thnPengeluaran += nom;
                    
                    if (dt.month == _selectedMonth) {
                      isMasuk ? _blnPemasukan += nom : _blnPengeluaran += nom;
                      _filteredDocs.add(doc);
                    }
                  }
                }

                int thnSaldo = thnPemasukan - thnPengeluaran;
                int blnSaldo = _blnPemasukan - _blnPengeluaran;

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.indigo.shade900, Colors.blue.shade800], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("SALDO TAHUN $_selectedYear", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 5),
                          Text(_currencyFormat.format(thnSaldo), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 15),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text("Masuk", style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                                Text(_currencyFormat.format(thnPemasukan), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              ]),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                const Text("Keluar", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                                Text(_currencyFormat.format(thnPengeluaran), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              ]),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),

                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.indigo.shade50)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Bulan ${_months[_selectedMonth - 1]}", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                              Text(_currencyFormat.format(blnSaldo), style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.bold, fontSize: 18)),
                            ],
                          ),
                          Row(
                            children: [
                              const Icon(Icons.arrow_downward, color: Colors.green, size: 16),
                              Text(_currencyFormat.format(_blnPemasukan), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(width: 10),
                              const Icon(Icons.arrow_upward, color: Colors.red, size: 16),
                              Text(_currencyFormat.format(_blnPengeluaran), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _showAddTransactionDialog(true),
                            icon: const Icon(Icons.add_circle, size: 18),
                            label: const Text("Pemasukan"),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _showAddTransactionDialog(false),
                            icon: const Icon(Icons.remove_circle, size: 18),
                            label: const Text("Pengeluaran"),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),

                    // 👇 JUDUL RIWAYAT + TOMBOL DOWNLOAD SULTAN 👇
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Riwayat ${_months[_selectedMonth - 1]} $_selectedYear", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
                        InkWell(
                          onTap: _showExportOptions,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.indigo.shade200)),
                            child: const Row(children: [Icon(Icons.download, size: 16, color: Colors.indigo), SizedBox(width: 4), Text("Ekspor", style: TextStyle(color: Colors.indigo, fontSize: 12, fontWeight: FontWeight.bold))]),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (_filteredDocs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(30.0),
                        child: Center(child: Text("Belum ada transaksi di bulan ini.", style: TextStyle(color: Colors.grey.shade500))),
                      )
                    else
                      ..._filteredDocs.map((doc) {
                        var data = doc.data() as Map<String, dynamic>;
                        bool isPemasukan = data['jenis'] == "Pemasukan";
                        Timestamp ts = data['tanggal'];
                        return Card(
                          elevation: 0, color: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isPemasukan ? Colors.green.shade50 : Colors.red.shade50,
                              child: Icon(isPemasukan ? Icons.south_west : Icons.north_east, color: isPemasukan ? Colors.green : Colors.red, size: 20),
                            ),
                            title: Text(data['keterangan'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Text(DateFormat('dd MMM yyyy').format(ts.toDate()), style: const TextStyle(fontSize: 11)),
                            trailing: Text(
                              isPemasukan ? "+ ${_currencyFormat.format(data['nominal'])}" : "- ${_currencyFormat.format(data['nominal'])}",
                              style: TextStyle(fontWeight: FontWeight.bold, color: isPemasukan ? Colors.green : Colors.red),
                            ),
                            onLongPress: () => _showOptionsBottomSheet(doc.id, data), 
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 👇 TAB 2: PERPULUHAN 👇
// ============================================================================
class _PerpuluhanTab extends StatefulWidget {
  final String namaDaerah;
  const _PerpuluhanTab({required this.namaDaerah});

  @override
  State<_PerpuluhanTab> createState() => _PerpuluhanTabState();
}

class _PerpuluhanTabState extends State<_PerpuluhanTab> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  List<QueryDocumentSnapshot> _filteredDocs = [];
  int _blnTotal = 0;

  final List<int> _years = List.generate(5, (index) => DateTime.now().year - index);
  final List<String> _months = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];

  List<String> _listGereja = [];
  List<String> _listPengerja = [];

  @override
  void initState() {
    super.initState();
    _fetchSuggestions(); 
  }

  Future<void> _fetchSuggestions() async {
    try {
      var snap = await _db.collection("churches").where("daerah", isEqualTo: widget.namaDaerah).get();
      Set<String> setGereja = {};
      Set<String> setPengerja = {};

      for (var doc in snap.docs) {
        var data = doc.data();
        String nmGereja = data['namaGereja'] ?? data['churchName'] ?? data['nama'] ?? "";
        String nmGembala = data['namaGembala'] ?? "";

        if (nmGereja.trim().isNotEmpty) setGereja.add(nmGereja.trim());
        if (nmGembala.trim().isNotEmpty && nmGembala != "Belum ada data Gembala") setPengerja.add(nmGembala.trim());
      }

      if (mounted) {
        setState(() { _listGereja = setGereja.toList()..sort(); _listPengerja = setPengerja.toList()..sort(); });
      }
    } catch (e) {
      debugPrint("Gagal load suggestions: $e");
    }
  }

  // 👇 FUNGSI EKSPORT PDF PERPULUHAN 👇
  Future<void> _exportToPDF() async {
    if (_filteredDocs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tidak ada data untuk diekspor!")));
      return;
    }

    final pdf = pw.Document();
    final String blnStr = _months[_selectedMonth - 1];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("Laporan Perpuluhan Daerah ${widget.namaDaerah}", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text("Periode: $blnStr $_selectedYear", style: const pw.TextStyle(fontSize: 14)),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headers: ['Tanggal', 'Tipe', 'Nama Penyetor', 'Nominal (Rp)'],
                data: _filteredDocs.map((doc) {
                  var d = doc.data() as Map<String, dynamic>;
                  DateTime dt = (d['tanggal'] as Timestamp).toDate();
                  return [
                    DateFormat('dd MMM yyyy').format(dt),
                    d['tipe'],
                    d['nama'],
                    _currencyFormat.format(d['nominal']).replaceAll("Rp ", "")
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.deepOrange900),
                cellAlignment: pw.Alignment.centerLeft,
              ),
              pw.SizedBox(height: 20),
              pw.Text("Total Setoran Bulan Ini: ${_currencyFormat.format(_blnTotal)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.deepOrange)),
            ],
          );
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Perpuluhan_${widget.namaDaerah}_${blnStr}_$_selectedYear.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: 'Laporan Perpuluhan Daerah ${widget.namaDaerah}');
  }

  // 👇 FUNGSI EKSPORT CSV (EXCEL) PERPULUHAN 👇
  Future<void> _exportToCSV() async {
    if (_filteredDocs.isEmpty) return;

    String csvData = "Tanggal,Tipe Sumber,Nama Penyetor,Nominal\n";
    for (var doc in _filteredDocs) {
      var d = doc.data() as Map<String, dynamic>;
      DateTime dt = (d['tanggal'] as Timestamp).toDate();
      String tgl = DateFormat('yyyy-MM-dd').format(dt);
      String nama = d['nama'].toString().replaceAll('"', '""'); 
      csvData += "$tgl,${d['tipe']},\"$nama\",${d['nominal']}\n";
    }

    final String blnStr = _months[_selectedMonth - 1];
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Perpuluhan_${widget.namaDaerah}_${blnStr}_$_selectedYear.csv');
    await file.writeAsString(csvData);
    await Share.shareXFiles([XFile(file.path)], text: 'Data CSV Perpuluhan ${widget.namaDaerah}');
  }

  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            const Padding(padding: EdgeInsets.all(16), child: Text("Cetak / Ekspor Laporan", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange))),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text("Ekspor sebagai PDF", style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () { Navigator.pop(ctx); _exportToPDF(); },
            ),
            ListTile(
              leading: const Icon(Icons.table_view, color: Colors.green),
              title: const Text("Ekspor sebagai CSV (Excel)", style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () { Navigator.pop(ctx); _exportToCSV(); },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showAddPerpuluhanDialog() => _showPerpuluhanForm();

  void _showEditPerpuluhanDialog(String docId, Map<String, dynamic> data) {
    _showPerpuluhanForm(
      docId: docId,
      initialTipe: data['tipe'],
      initialNama: data['nama'],
      initialNominal: data['nominal'].toString(),
      initialDate: (data['tanggal'] as Timestamp?)?.toDate(),
    );
  }

  void _showPerpuluhanForm({String? docId, String? initialTipe, String? initialNama, String? initialNominal, DateTime? initialDate}) {
    // 🔥 FORMAT AWAL SAAT EDIT 🔥
    String formattedNominal = "";
    if (initialNominal != null && initialNominal.isNotEmpty) {
      formattedNominal = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(int.parse(initialNominal));
    }

    final etNominal = TextEditingController(text: formattedNominal);
    String tipeSumber = initialTipe ?? "Gereja Lokal";
    DateTime selectedDate = initialDate ?? DateTime.now(); 
    TextEditingController? autoNameController;
    bool isEdit = docId != null;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(isEdit ? Icons.edit : Icons.volunteer_activism, color: isEdit ? Colors.blue : Colors.orange),
              const SizedBox(width: 8),
              Text(isEdit ? "Edit Perpuluhan" : "Input Perpuluhan", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () async {
                    DateTime? picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (picked != null) setStateDialog(() => selectedDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(5)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(DateFormat('dd MMMM yyyy').format(selectedDate), style: const TextStyle(fontSize: 15)),
                        const Icon(Icons.calendar_month, color: Colors.orange),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                DropdownButtonFormField<String>(
                  value: tipeSumber,
                  decoration: const InputDecoration(labelText: "Sumber", border: OutlineInputBorder()),
                  items: ["Gereja Lokal", "Pengerja (Hamba Tuhan)", "Donatur Lain"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (val) {
                    setStateDialog(() {
                      tipeSumber = val!;
                      autoNameController?.clear();
                    });
                  },
                ),
                const SizedBox(height: 15),
                
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: initialNama ?? ""),
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty || tipeSumber == "Donatur Lain") return const Iterable<String>.empty();
                    List<String> sourceList = [];
                    if (tipeSumber == "Gereja Lokal") sourceList = _listGereja;
                    if (tipeSumber == "Pengerja (Hamba Tuhan)") sourceList = _listPengerja;
                    return sourceList.where((String option) => option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                  },
                  onSelected: (String selection) => autoNameController?.text = selection,
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    autoNameController = controller; 
                    return TextField(
                      controller: controller, focusNode: focusNode, textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: "Nama Pengerja / Gereja", hintText: "Ketik nama...", border: OutlineInputBorder(), suffixIcon: Icon(Icons.search, color: Colors.grey)),
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 8.0, borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 250, constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.separated(
                            padding: EdgeInsets.zero, shrinkWrap: true, itemCount: options.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final String option = options.elementAt(index);
                              return ListTile(dense: true, title: Text(option, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)), onTap: () => onSelected(option));
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 15),
                
                TextField(
                  controller: etNominal, 
                  keyboardType: TextInputType.number, 
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    CurrencyInputFormatter() // 👈 SISIPKAN FORMATTER TITIK OTOMATIS
                  ],
                  decoration: const InputDecoration(labelText: "Nominal", border: OutlineInputBorder(), prefixText: "Rp ")
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Batal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: isEdit ? Colors.blue : Colors.indigo, foregroundColor: Colors.white),
              onPressed: () async {
                String inputNama = autoNameController?.text.trim() ?? "";
                if (inputNama.isEmpty || etNominal.text.trim().isEmpty) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠ Mohon lengkapi semua data!"), backgroundColor: Colors.orange));
                   return;
                }
                
                int nom = int.tryParse(etNominal.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                if (nom <= 0) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠ Nominal tidak valid!"), backgroundColor: Colors.orange));
                   return;
                }

                Navigator.pop(dialogContext);

                try {
                  WriteBatch batch = _db.batch();

                  if (isEdit) {
                    DocumentReference refPerpuluhan = _db.collection("perpuluhan_daerah").doc(docId);
                    DocumentReference refKas = _db.collection("keuangan_daerah").doc(docId);

                    batch.update(refPerpuluhan, {
                      "tipe": tipeSumber, "nama": inputNama, "nominal": nom, "tanggal": Timestamp.fromDate(selectedDate),
                    });
                    
                    batch.set(refKas, {
                      "daerah": widget.namaDaerah, "jenis": "Pemasukan", "nominal": nom,
                      "keterangan": "Perpuluhan: $inputNama", "tanggal": Timestamp.fromDate(selectedDate),
                    }, SetOptions(merge: true));

                    await batch.commit();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Perpuluhan direvisi & Kas disesuaikan!"), backgroundColor: Colors.blue));
                  } else {
                    DocumentReference docRef = _db.collection("perpuluhan_daerah").doc();
                    batch.set(docRef, {
                      "daerah": widget.namaDaerah, "tipe": tipeSumber, "nama": inputNama,
                      "nominal": nom, "tanggal": Timestamp.fromDate(selectedDate),
                    });
                    batch.set(_db.collection("keuangan_daerah").doc(docRef.id), {
                      "daerah": widget.namaDaerah, "jenis": "Pemasukan", "nominal": nom,
                      "keterangan": "Perpuluhan: $inputNama", "tanggal": Timestamp.fromDate(selectedDate),
                    });

                    await batch.commit();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Perpuluhan dicatat & masuk ke Kas!"), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Gagal menyimpan: $e"), backgroundColor: Colors.red));
                }
              },
              child: Text(isEdit ? "Simpan Perubahan" : "Simpan"),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptionsBottomSheet(String docId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text("Edit Perpuluhan", style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () { Navigator.pop(ctx); _showEditPerpuluhanDialog(docId, data); },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Hapus Perpuluhan", style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () { Navigator.pop(ctx); _showDeleteDialog(docId, data['nama']); },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(String docId, String nama) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Hapus Data?"),
        content: Text("Yakin menghapus setoran dari $nama? (Data di Kas Operasional juga akan terhapus)"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              WriteBatch batch = _db.batch();
              batch.delete(_db.collection("perpuluhan_daerah").doc(docId));
              batch.delete(_db.collection("keuangan_daerah").doc(docId));
              await batch.commit();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data dihapus")));
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.white)),
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _months[_selectedMonth - 1],
                    decoration: InputDecoration(labelText: "Bulan", contentPadding: const EdgeInsets.symmetric(horizontal: 15), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    items: _months.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14)))).toList(),
                    onChanged: (val) => setState(() => _selectedMonth = _months.indexOf(val!) + 1),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedYear,
                    decoration: InputDecoration(labelText: "Tahun", contentPadding: const EdgeInsets.symmetric(horizontal: 15), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    items: _years.map((e) => DropdownMenuItem(value: e, child: Text(e.toString(), style: const TextStyle(fontSize: 14)))).toList(),
                    onChanged: (val) => setState(() => _selectedYear = val!),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection("perpuluhan_daerah").where("daerah", isEqualTo: widget.namaDaerah).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                var docs = snapshot.data?.docs.toList() ?? [];
                
                docs.sort((a, b) {
                  Timestamp tA = (a.data() as Map<String, dynamic>)['tanggal'] ?? Timestamp.now();
                  Timestamp tB = (b.data() as Map<String, dynamic>)['tanggal'] ?? Timestamp.now();
                  return tB.compareTo(tA);
                });
                
                int thnTotal = 0;
                _blnTotal = 0;
                _filteredDocs = [];

                for (var doc in docs) {
                  var data = doc.data() as Map<String, dynamic>;
                  Timestamp? ts = data['tanggal'] as Timestamp?;
                  if (ts == null) continue;

                  DateTime dt = ts.toDate();
                  int nom = data['nominal'] ?? 0;

                  if (dt.year == _selectedYear) {
                    thnTotal += nom;
                    if (dt.month == _selectedMonth) {
                      _blnTotal += nom;
                      _filteredDocs.add(doc);
                    }
                  }
                }

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.orange.shade900, Colors.deepOrange.shade600], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("TOTAL PERPULUHAN TAHUN $_selectedYear", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 5),
                          Text(_currencyFormat.format(thnTotal), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 15),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text("Bulan ${_months[_selectedMonth - 1]}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                Text(_currencyFormat.format(_blnTotal), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              ]),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),

                    // 👇 JUDUL RIWAYAT + TOMBOL DOWNLOAD SULTAN 👇
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Setoran ${_months[_selectedMonth - 1]} $_selectedYear", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
                        InkWell(
                          onTap: _showExportOptions,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.orange.shade200)),
                            child: const Row(children: [Icon(Icons.download, size: 16, color: Colors.orange), SizedBox(width: 4), Text("Ekspor", style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold))]),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (_filteredDocs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(30.0),
                        child: Center(child: Text("Belum ada perpuluhan di bulan ini.", style: TextStyle(color: Colors.grey.shade500))),
                      )
                    else
                      ..._filteredDocs.map((doc) {
                        var data = doc.data() as Map<String, dynamic>;
                        Timestamp ts = data['tanggal'];
                        
                        return Card(
                          elevation: 0, margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade200)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.shade50,
                              child: Icon(data['tipe'] == "Gereja Lokal" ? Icons.church : Icons.person, color: Colors.orange),
                            ),
                            title: Text(data['nama'], style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("${data['tipe']} • ${DateFormat('dd MMM yyyy').format(ts.toDate())}", style: const TextStyle(fontSize: 11)),
                            trailing: Text(_currencyFormat.format(data['nominal']), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 14)),
                            onLongPress: () => _showOptionsBottomSheet(doc.id, data), 
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddPerpuluhanDialog,
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text("Input Perpuluhan"),
      ),
    );
  }
}