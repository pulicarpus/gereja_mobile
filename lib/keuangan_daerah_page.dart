import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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
// 👇 TAB 1: KAS OPERASIONAL DAERAH (DENGAN FILTER TAHUN & BULAN) 👇
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

  final List<int> _years = List.generate(5, (index) => DateTime.now().year - index);
  final List<String> _months = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];

  void _showAddTransactionDialog(bool isPemasukan) {
    final etNominal = TextEditingController();
    final etKeterangan = TextEditingController();
    String jenis = isPemasukan ? "Pemasukan" : "Pengeluaran";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(isPemasukan ? Icons.south_west : Icons.north_east, color: isPemasukan ? Colors.green : Colors.red),
            const SizedBox(width: 8),
            Text("Tambah $jenis", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: etNominal,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Nominal (Angka Saja)", border: OutlineInputBorder(), prefixText: "Rp "),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: etKeterangan,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: "Keterangan", hintText: "Cth: Konsumsi Rapat", border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: isPemasukan ? Colors.green : Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              if (etNominal.text.isEmpty || etKeterangan.text.isEmpty) return;
              int nominal = int.tryParse(etNominal.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              if (nominal <= 0) return;

              Navigator.pop(context);
              await _db.collection("keuangan_daerah").add({
                "daerah": widget.namaDaerah,
                "jenis": jenis,
                "nominal": nominal,
                "keterangan": etKeterangan.text.trim(),
                "tanggal": FieldValue.serverTimestamp(),
              });
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$jenis berhasil dicatat!")));
            },
            child: const Text("Simpan"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: Column(
        children: [
          // FILTER TAHUN & BULAN
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
              stream: _db.collection("keuangan_daerah").where("daerah", isEqualTo: widget.namaDaerah).orderBy("tanggal", descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                
                var docs = snapshot.data?.docs ?? [];
                
                int thnPemasukan = 0, thnPengeluaran = 0;
                int blnPemasukan = 0, blnPengeluaran = 0;
                List<QueryDocumentSnapshot> filteredDocs = [];

                // MESIN FILTERING (Anti Error Index Firebase)
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
                      isMasuk ? blnPemasukan += nom : blnPengeluaran += nom;
                      filteredDocs.add(doc);
                    }
                  }
                }

                int thnSaldo = thnPemasukan - thnPengeluaran;
                int blnSaldo = blnPemasukan - blnPengeluaran;

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // KARTU SALDO TAHUNAN
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

                    // KARTU SALDO BULANAN
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
                              Text(_currencyFormat.format(blnPemasukan), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(width: 10),
                              const Icon(Icons.arrow_upward, color: Colors.red, size: 16),
                              Text(_currencyFormat.format(blnPengeluaran), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),

                    // TOMBOL INPUT SULTAN
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

                    // DAFTAR TRANSAKSI BULAN INI
                    Text("Riwayat ${_months[_selectedMonth - 1]} $_selectedYear", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
                    const SizedBox(height: 10),

                    if (filteredDocs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(30.0),
                        child: Center(child: Text("Belum ada transaksi di bulan ini.", style: TextStyle(color: Colors.grey.shade500))),
                      )
                    else
                      ...filteredDocs.map((doc) {
                        var data = doc.data() as Map<String, dynamic>;
                        bool isPemasukan = data['jenis'] == "Pemasukan";
                        Timestamp ts = data['tanggal'];
                        return Card(
                          elevation: 0,
                          color: Colors.white,
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
// 👇 TAB 2: PERPULUHAN PENGERJA / GEREJA LOKAL 👇
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

  void _showAddPerpuluhanDialog() {
    final etNama = TextEditingController();
    final etNominal = TextEditingController();
    String tipeSumber = "Gereja Lokal";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Input Perpuluhan", style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: tipeSumber,
                decoration: const InputDecoration(labelText: "Sumber", border: OutlineInputBorder()),
                items: ["Gereja Lokal", "Pengerja (Hamba Tuhan)", "Donatur Lain"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (val) => setStateDialog(() => tipeSumber = val!),
              ),
              const SizedBox(height: 15),
              TextField(controller: etNama, decoration: const InputDecoration(labelText: "Nama Gereja / Pengerja", hintText: "Cth: GKII Siloam", border: OutlineInputBorder())),
              const SizedBox(height: 15),
              TextField(controller: etNominal, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Nominal Perpuluhan", border: OutlineInputBorder(), prefixText: "Rp ")),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: () async {
                if (etNama.text.isEmpty || etNominal.text.isEmpty) return;
                int nom = int.tryParse(etNominal.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                if (nom <= 0) return;

                Navigator.pop(context);
                await _db.collection("perpuluhan_daerah").add({
                  "daerah": widget.namaDaerah,
                  "tipe": tipeSumber,
                  "nama": etNama.text.trim(),
                  "nominal": nom,
                  "tanggal": FieldValue.serverTimestamp(),
                });
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Perpuluhan dicatat!")));
              },
              child: const Text("Simpan"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection("perpuluhan_daerah").where("daerah", isEqualTo: widget.namaDaerah).orderBy("tanggal", descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          var docs = snapshot.data?.docs ?? [];
          
          if (docs.isEmpty) {
             return const Center(child: Text("Belum ada data perpuluhan.", style: TextStyle(color: Colors.grey)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data() as Map<String, dynamic>;
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
                ),
              );
            },
          );
        }
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