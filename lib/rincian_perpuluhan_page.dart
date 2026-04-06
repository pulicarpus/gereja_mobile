import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'user_manager.dart';
// import 'tambah_perpuluhan_page.dart'; // Buka komen ini saat file Tambah Perpuluhan sudah kita buat

// --- DATA CLASS ---
class PerpuluhanItem {
  String id;
  int jumlah;
  String? jemaatId;
  String? namaJemaat;
  DateTime? tanggal;

  PerpuluhanItem({
    required this.id,
    required this.jumlah,
    this.jemaatId,
    this.namaJemaat,
    this.tanggal,
  });
}

class RincianPerpuluhanPage extends StatefulWidget {
  final String? jemaatId;
  final String? namaJemaat;
  final int bulan; // 0 = Jan, 11 = Des (Bawaan dari Android)
  final int tahun;

  const RincianPerpuluhanPage({
    super.key,
    this.jemaatId,
    this.namaJemaat,
    required this.bulan,
    required this.tahun,
  });

  @override
  State<RincianPerpuluhanPage> createState() => _RincianPerpuluhanPageState();
}

class _RincianPerpuluhanPageState extends State<RincianPerpuluhanPage> {
  final _db = FirebaseFirestore.instance;
  List<PerpuluhanItem> _perpuluhanList = [];
  bool _isLoading = false;

  final List<String> _bulanArray = [
    "Januari", "Februari", "Maret", "April", "Mei", "Juni", 
    "Juli", "Agustus", "September", "Oktober", "November", "Desember"
  ];

  @override
  void initState() {
    super.initState();
    _loadRincian();
  }

  Future<void> _loadRincian() async {
    setState(() => _isLoading = true);
    
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Konversi bulan Android (0-11) ke bulan Flutter (1-12)
    DateTime startDate = DateTime(widget.tahun, widget.bulan + 1, 1);
    DateTime endDate = DateTime(widget.tahun, widget.bulan + 2, 0, 23, 59, 59);

    try {
      var query = _db.collection("churches").doc(churchId).collection("perpuluhan")
          .where("tanggal", isGreaterThanOrEqualTo: startDate)
          .where("tanggal", isLessThanOrEqualTo: endDate);

      // Filter berdasarkan ID atau Nama (Sesuai logika Kotlin Bos)
      if (widget.jemaatId != null && widget.jemaatId!.isNotEmpty) {
        query = query.where("jemaatId", isEqualTo: widget.jemaatId);
      } else {
        query = query.where("namaJemaat", isEqualTo: widget.namaJemaat);
      }

      var snap = await query.orderBy("tanggal", descending: true).get();

      List<PerpuluhanItem> tempList = [];
      for (var doc in snap.docs) {
        var data = doc.data();
        tempList.add(PerpuluhanItem(
          id: doc.id,
          jumlah: (data['jumlah'] ?? 0) as int,
          jemaatId: data['jemaatId'] as String?,
          namaJemaat: data['namaJemaat'] as String?,
          tanggal: (data['tanggal'] as Timestamp?)?.toDate(),
        ));
      }

      setState(() => _perpuluhanList = tempList);

      if (tempList.isEmpty && mounted) {
        _showSnack("Tidak ada data rincian di periode ini.");
      }
    } catch (e) {
      _showSnack("Error memuat rincian: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String formatRupiah(int amount) {
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);
  }

  String formatTanggal(DateTime? date) {
    if (date == null) return "Tanggal tidak valid";
    return DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(date);
  }

  void _showSnack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- MENU KLIK LAMA (Khusus Admin) ---
  void _showOptionsDialog(PerpuluhanItem perpuluhan) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(15),
              child: Text("Pilih Aksi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text("Edit Transaksi Ini"),
              onTap: () {
                Navigator.pop(context);
                _navigateToEdit(perpuluhan);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Hapus Transaksi Ini"),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmationDialog(perpuluhan);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEdit(PerpuluhanItem perpuluhan) {
    // Navigasi ke Edit dan Refresh saat kembali
    /* Navigator.push(context, MaterialPageRoute(builder: (_) => TambahPerpuluhanPage(
      perpuluhanEdit: perpuluhan,
    ))).then((_) => _loadRincian()); // Refresh data otomatis layaknya onResume()
    */
    _showSnack("Navigasi ke halaman Edit (Segera dibuat)");
  }

  void _showDeleteConfirmationDialog(PerpuluhanItem perpuluhan) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Konfirmasi Hapus"),
        content: const Text("Yakin ingin menghapus transaksi perpuluhan ini?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              _deletePerpuluhan(perpuluhan);
            },
            child: const Text("Ya, Hapus"),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePerpuluhan(PerpuluhanItem perpuluhan) async {
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) return;

    try {
      await _db.collection("churches").doc(churchId).collection("perpuluhan").doc(perpuluhan.id).delete();
      _showSnack("Transaksi berhasil dihapus.");
      _loadRincian(); // Refresh list
    } catch (e) {
      _showSnack("Gagal menghapus transaksi.");
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isAdmin = UserManager().isAdmin();
    String nama = widget.namaJemaat ?? "Jemaat";
    String bulanStr = _bulanArray[widget.bulan];

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Rincian Perpuluhan"),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Subtitle Banner (Menggantikan Text biasa di Android)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nama, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                const SizedBox(height: 5),
                Text("Periode: $bulanStr ${widget.tahun}", style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          
          // Daftar Rincian (Menggantikan RecyclerView)
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _perpuluhanList.isEmpty
                    ? const Center(child: Text("Belum ada transaksi.", style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        itemCount: _perpuluhanList.length,
                        itemBuilder: (context, index) {
                          var item = _perpuluhanList[index];
                          
                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              // LONG PRESS HANYA AKTIF JIKA ADMIN (Translasi logika Android)
                              onLongPress: isAdmin ? () => _showOptionsDialog(item) : null,
                              child: Padding(
                                padding: const EdgeInsets.all(15),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text("Tanggal Masuk", style: TextStyle(fontSize: 12, color: Colors.grey)),
                                        const SizedBox(height: 4),
                                        Text(formatTanggal(item.tanggal), style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    Text(
                                      formatRupiah(item.jumlah),
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
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
    );
  }
}