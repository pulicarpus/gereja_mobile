import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'user_manager.dart';

class DataJemaatPage extends StatefulWidget {
  final String? filterKategorial; // Untuk menangani filter dari menu Kategorial

  const DataJemaatPage({super.key, this.filterKategorial});

  @override
  State<DataJemaatPage> createState() => _DataJemaatPageState();
}

class _DataJemaatPageState extends State<DataJemaatPage> {
  final _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  
  List<Map<String, dynamic>> _allJemaat = [];
  List<Map<String, dynamic>> _filteredJemaat = [];
  List<String> _ultahMingguIni = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadJemaat();
  }

  // Fungsi Load Data persis seperti di Kotlin
  void _loadJemaat() async {
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) return;

    try {
      Query query = _db.collection("churches").doc(churchId).collection("jemaat");

      // Jika ada filter kategorial (misal: Pemuda, Pria, Wanita)
      if (widget.filterKategorial != null) {
        query = query.where("kelompok", isEqualTo: widget.filterKategorial);
      }

      final snapshot = await query.get();
      final List<Map<String, dynamic>> tempData = snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();

      // Urutkan berdasarkan nama
      tempData.sort((a, b) => (a['namaLengkap'] ?? "").toString().toLowerCase()
          .compareTo((b['namaLengkap'] ?? "").toString().toLowerCase()));

      if (mounted) {
        setState(() {
          _allJemaat = tempData;
          _filteredJemaat = tempData;
          _checkBirthday(tempData);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  // Logika Cek Ulang Tahun 7 hari terakhir
  void _checkBirthday(List<Map<String, dynamic>> list) {
    _ultahMingguIni.clear();
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 6));
    final df = DateFormat("dd-MM-yyyy");

    for (var jemaat in list) {
      try {
        DateTime birthDate = df.parse(jemaat['tanggalLahir'] ?? "");
        // Set tahun lahir ke tahun sekarang untuk perbandingan
        DateTime thisYearBirth = DateTime(now.year, birthDate.month, birthDate.day);

        if (thisYearBirth.isAfter(sevenDaysAgo.subtract(const Duration(days: 1))) && 
            thisYearBirth.isBefore(now.add(const Duration(days: 1)))) {
          _ultahMingguIni.add(jemaat['namaLengkap'] ?? "Tanpa Nama");
        }
      } catch (_) {}
    }
  }

  // Filter Search Real-time
  void _filterSearch(String query) {
    setState(() {
      _filteredJemaat = _allJemaat
          .where((j) => (j['namaLengkap'] ?? "").toString().toLowerCase()
          .contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = UserManager();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.filterKategorial ?? "Data Jemaat"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              onChanged: _filterSearch,
              decoration: InputDecoration(
                hintText: "Cari nama jemaat...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Card Statistik Kategorial
                if (widget.filterKategorial != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(10),
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "Total ${widget.filterKategorial}: ${_allJemaat.length} Orang",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Card Notifikasi Ulang Tahun
                if (_ultahMingguIni.isNotEmpty)
                  Card(
                    color: Colors.orange.shade50,
                    margin: const EdgeInsets.all(10),
                    child: ListTile(
                      leading: const Icon(Icons.cake, color: Colors.orange),
                      title: const Text("Ultah Minggu Ini:", style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(_ultahMingguIni.join(", ")),
                    ),
                  ),

                // Tombol Statistik & Keluarga (Hanya muncul jika bukan mode filter)
                if (widget.filterKategorial == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {}, 
                            icon: const Icon(Icons.bar_chart), 
                            label: const Text("Statistik"),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {}, 
                            icon: const Icon(Icons.family_restroom), 
                            label: const Text("Keluarga"),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Daftar Jemaat
                Expanded(
                  child: _filteredJemaat.isEmpty
                      ? const Center(child: Text("Data tidak ditemukan"))
                      : ListView.builder(
                          itemCount: _filteredJemaat.length,
                          itemBuilder: (context, index) {
                            final j = _filteredJemaat[index];
                            return ListTile(
                              leading: CircleAvatar(child: Text(j['namaLengkap']?[0] ?? "?")),
                              title: Text(j['namaLengkap'] ?? "Tanpa Nama"),
                              subtitle: Text("${j['status'] ?? ''} - ${j['kelompok'] ?? ''}"),
                              trailing: user.isAdmin() 
                                  ? IconButton(icon: const Icon(Icons.edit), onPressed: () {}) 
                                  : const Icon(Icons.chevron_right),
                              onTap: () {
                                // Fungsi View Detail
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
      // FAB Tambah Jemaat (Hanya untuk Admin)
      floatingActionButton: user.isAdmin() 
          ? FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}