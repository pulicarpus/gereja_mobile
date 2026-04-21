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

  final List<int> _years = List.generate(5, (index) => DateTime.now().year - index);
  final List<String> _months = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];

  void _showAddTransactionDialog(bool isPemasukan) {
    final etNominal = TextEditingController();
    final etKeterangan = TextEditingController();
    String jenis = isPemasukan ? "Pemasukan" : "Pengeluaran";

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: isPemasukan ? Colors.green : Colors.red, foregroundColor: Colors.white),
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
                await _db.collection("keuangan_daerah").add({
                  "daerah": widget.namaDaerah,
                  "jenis": jenis,
                  "nominal": nominal,
                  "keterangan": etKeterangan.text.trim(),
                  "tanggal": FieldValue.serverTimestamp(),
                });
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ $jenis berhasil dicatat!"), backgroundColor: Colors.green));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Gagal menyimpan: $e"), backgroundColor: Colors.red));
              }
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
                            onLongPress: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text("Hapus Transaksi?"),
                                  content: Text("Yakin ingin menghapus ${data['keterangan']}?"),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      onPressed: () {
                                        _db.collection("keuangan_daerah").doc(doc.id).delete();
                                        Navigator.pop(ctx);
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data dihapus")));
                                      },
                                      child: const Text("Hapus", style: TextStyle(color: Colors.white)),
                                    )
                                  ],
                                )
                              );
                            },
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
// 👇 TAB 2: PERPULUHAN (DENGAN AUTOCOMPLETE PINTAR) 👇
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

  // 👇 PENAMPUNG DATA OTOMATIS 👇
  List<String> _listGereja = [];
  List<String> _listPengerja = [];

  @override
  void initState() {
    super.initState();
    _fetchSuggestions(); // Sedot data nama-nama dari Firebase saat halaman dibuka
  }

  // MESIN PENYEDOT DATA GEREJA & PENGERJA
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
        if (nmGembala.trim().isNotEmpty && nmGembala != "Belum ada data Gembala") {
          setPengerja.add(nmGembala.trim());
        }
      }

      if (mounted) {
        setState(() {
          _listGereja = setGereja.toList()..sort();
          _listPengerja = setPengerja.toList()..sort();
        });
      }
    } catch (e) {
      debugPrint("Gagal load suggestions: $e");
    }
  }

  void _showAddPerpuluhanDialog() {
    final etNominal = TextEditingController();
    String tipeSumber = "Gereja Lokal";
    
    // Variabel penangkap ketikan dari Autocomplete
    TextEditingController? autoNameController;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
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
                onChanged: (val) {
                  setStateDialog(() {
                    tipeSumber = val!;
                    autoNameController?.clear(); // Bersihkan nama kalau tipenya diganti
                  });
                },
              ),
              const SizedBox(height: 15),
              
              // 👇 FITUR AUTOCOMPLETE (SARAN OTOMATIS) 👇
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty || tipeSumber == "Donatur Lain") {
                    return const Iterable<String>.empty();
                  }
                  
                  List<String> sourceList = [];
                  if (tipeSumber == "Gereja Lokal") sourceList = _listGereja;
                  if (tipeSumber == "Pengerja (Hamba Tuhan)") sourceList = _listPengerja;
                  
                  return sourceList.where((String option) {
                    return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                  });
                },
                onSelected: (String selection) {
                  autoNameController?.text = selection;
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  autoNameController = controller; // Tangkap controllernya
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: "Nama Pengerja / Gereja",
                      hintText: "Ketik nama...",
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.search, color: Colors.grey),
                    ),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 8.0,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 250, // Lebar dropdown
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final String option = options.elementAt(index);
                            return ListTile(
                              dense: true,
                              title: Text(option, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
                              onTap: () => onSelected(option),
                            );
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
                decoration: const InputDecoration(labelText: "Nominal Perpuluhan", border: OutlineInputBorder(), prefixText: "Rp ")
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Batal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
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
                  await _db.collection("perpuluhan_daerah").add({
                    "daerah": widget.namaDaerah,
                    "tipe": tipeSumber,
                    "nama": inputNama,
                    "nominal": nom,
                    "tanggal": FieldValue.serverTimestamp(),
                  });
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Perpuluhan berhasil dicatat!"), backgroundColor: Colors.green));
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Gagal menyimpan: $e"), backgroundColor: Colors.red));
                }
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
                  onLongPress: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("Hapus Data?"),
                        content: Text("Yakin ingin menghapus setoran dari ${data['nama']}?"),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () {
                              _db.collection("perpuluhan_daerah").doc(docs[index].id).delete();
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data dihapus")));
                            },
                            child: const Text("Hapus", style: TextStyle(color: Colors.white)),
                          )
                        ],
                      )
                    );
                  },
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