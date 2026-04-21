import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class KeuanganDaerahPage extends StatefulWidget {
  final String namaDaerah;

  const KeuanganDaerahPage({super.key, required this.namaDaerah});

  @override
  State<KeuanganDaerahPage> createState() => _KeuanganDaerahPageState();
}

class _KeuanganDaerahPageState extends State<KeuanganDaerahPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Format Rupiah
  final NumberFormat currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  // 👇 DIALOG TAMBAH TRANSAKSI KAS DAERAH 👇
  void _showAddTransactionDialog() {
    String jenisTransaksi = "Pemasukan";
    final etNominal = TextEditingController();
    final etKeterangan = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Tambah Transaksi", style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: jenisTransaksi,
                    decoration: const InputDecoration(labelText: "Jenis Transaksi", border: OutlineInputBorder()),
                    items: ["Pemasukan", "Pengeluaran"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) => setStateDialog(() => jenisTransaksi = val!),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: etNominal,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Nominal (Angka Saja)", hintText: "Contoh: 500000", border: OutlineInputBorder(), prefixText: "Rp "),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: etKeterangan,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: "Keterangan", hintText: "Cth: Iuran GKII Siloam", border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                onPressed: () async {
                  if (etNominal.text.isEmpty || etKeterangan.text.isEmpty) return;

                  int nominal = int.tryParse(etNominal.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                  if (nominal <= 0) return;

                  Navigator.pop(context);

                  // Simpan ke koleksi khusus keuangan daerah
                  await _db.collection("keuangan_daerah").add({
                    "daerah": widget.namaDaerah,
                    "jenis": jenisTransaksi,
                    "nominal": nominal,
                    "keterangan": etKeterangan.text.trim(),
                    "tanggal": FieldValue.serverTimestamp(),
                  });

                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Transaksi berhasil dicatat!")));
                },
                child: const Text("Simpan"),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text("Kas Daerah ${widget.namaDaerah}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection("keuangan_daerah")
                   .where("daerah", isEqualTo: widget.namaDaerah)
                   .orderBy("tanggal", descending: true)
                   .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          var docs = snapshot.data?.docs ?? [];

          // Mesin Penghitung Saldo
          int totalPemasukan = 0;
          int totalPengeluaran = 0;

          for (var doc in docs) {
            var data = doc.data() as Map<String, dynamic>;
            int nominal = data['nominal'] ?? 0;
            if (data['jenis'] == "Pemasukan") {
              totalPemasukan += nominal;
            } else {
              totalPengeluaran += nominal;
            }
          }
          int saldo = totalPemasukan - totalPengeluaran;

          return Column(
            children: [
              // 👇 KARTU ATM SULTAN 👇
              Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.indigo.shade900, Colors.blue.shade800], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("TOTAL SALDO KAS DAERAH", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 5),
                    Text(currencyFormat.format(saldo), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.arrow_downward, color: Colors.greenAccent, size: 14),
                                SizedBox(width: 4),
                                Text("Pemasukan", style: TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(currencyFormat.format(totalPemasukan), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.arrow_upward, color: Colors.redAccent, size: 14),
                                SizedBox(width: 4),
                                Text("Pengeluaran", style: TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(currencyFormat.format(totalPengeluaran), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    )
                  ],
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(alignment: Alignment.centerLeft, child: Text("Riwayat Transaksi", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo))),
              ),
              const SizedBox(height: 10),

              // 👇 DAFTAR TRANSAKSI 👇
              Expanded(
                child: docs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long, size: 60, color: Colors.grey.shade300),
                            const SizedBox(height: 10),
                            const Text("Belum ada riwayat transaksi", style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          var data = docs[index].data() as Map<String, dynamic>;
                          var docId = docs[index].id;
                          bool isPemasukan = data['jenis'] == "Pemasukan";
                          String ket = data['keterangan'] ?? "-";
                          int nom = data['nominal'] ?? 0;
                          
                          Timestamp? ts = data['tanggal'] as Timestamp?;
                          String tgl = ts != null ? DateFormat('dd MMM yyyy, HH:mm').format(ts.toDate()) : "-";

                          return Container(
                            margin: const EdgeInsets.only(bottom: 15),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: isPemasukan ? Colors.green.shade50 : Colors.red.shade50, shape: BoxShape.circle),
                                child: Icon(isPemasukan ? Icons.south_west : Icons.north_east, color: isPemasukan ? Colors.green : Colors.red),
                              ),
                              title: Text(ket, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(tgl, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    isPemasukan ? "+ ${currencyFormat.format(nom)}" : "- ${currencyFormat.format(nom)}",
                                    style: TextStyle(fontWeight: FontWeight.bold, color: isPemasukan ? Colors.green : Colors.red, fontSize: 14),
                                  ),
                                ],
                              ),
                              onLongPress: () {
                                // Opsi hapus jika ditahan lama
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text("Hapus Transaksi?"),
                                    content: Text("Yakin ingin menghapus transaksi '$ket'?"),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                        onPressed: () {
                                          _db.collection("keuangan_daerah").doc(docId).delete();
                                          Navigator.pop(context);
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
                      ),
              )
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTransactionDialog,
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}