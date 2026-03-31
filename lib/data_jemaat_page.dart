import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'user_manager.dart';

class DataJemaatPage extends StatefulWidget {
  final String? filterKategorial;

  const DataJemaatPage({super.key, this.filterKategorial});

  @override
  State<DataJemaatPage> createState() => _DataJemaatPageState();
}

class _DataJemaatPageState extends State<DataJemaatPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  
  List<Map<String, dynamic>> _allJemaat = [];
  List<Map<String, dynamic>> _filteredJemaat = [];
  List<String> _ultahMingguIni = [];
  bool _isLoading = true;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _loadJemaat();
  }

  // FUNGSI LOAD DATA DENGAN RADAR ERROR
  Future<void> _loadJemaat() async {
    String? churchId = UserManager().activeChurchId;
    
    // Debugging untuk terminal Acode
    debugPrint("DEBUG: Memulai load jemaat untuk ChurchID: $churchId");

    if (churchId == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "ID Gereja tidak ditemukan. Silakan login ulang.";
        });
      }
      return;
    }

    try {
      // 1. Referensi Koleksi
      Query query = _db.collection("churches").doc(churchId).collection("jemaat");

      // 2. Terapkan Filter jika ada
      if (widget.filterKategorial != null) {
        query = query.where("kelompok", isEqualTo: widget.filterKategorial);
      }

      // 3. Ambil Data dengan Timeout agar tidak loading selamanya
      final snapshot = await query.get().timeout(const Duration(seconds: 15));
      
      debugPrint("DEBUG: Berhasil konek ke Firestore. Dokumen ditemukan: ${snapshot.docs.length}");

      final List<Map<String, dynamic>> tempData = snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();

      // 4. Urutkan Nama
      tempData.sort((a, b) => (a['namaLengkap'] ?? "").toString().toLowerCase()
          .compareTo((b['namaLengkap'] ?? "").toString().toLowerCase()));

      if (mounted) {
        setState(() {
          _allJemaat = tempData;
          _filteredJemaat = tempData;
          _checkBirthday(tempData);
          _isLoading = false;
          _errorMessage = tempData.isEmpty ? "Belum ada data jemaat." : "";
        });
      }
    } catch (e) {
      debugPrint("DEBUG: ERROR FIRESTORE -> $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Gagal mengambil data: $e";
        });
      }
    }
  }

  // LOGIKA CEK ULTAH
  void _checkBirthday(List<Map<String, dynamic>> list) {
    _ultahMingguIni.clear();
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 6));
    final df = DateFormat("dd-MM-yyyy");

    for (var jemaat in list) {
      String? tgl = jemaat['tanggalLahir'];
      if (tgl == null || tgl.isEmpty) continue;
      
      try {
        DateTime birthDate = df.parse(tgl);
        DateTime thisYearBirth = DateTime(now.year, birthDate.month, birthDate.day);

        if (thisYearBirth.isAfter(sevenDaysAgo.subtract(const Duration(days: 1))) && 
            thisYearBirth.isBefore(now.add(const Duration(days: 1)))) {
          _ultahMingguIni.add(jemaat['namaLengkap'] ?? "Tanpa Nama");
        }
      } catch (e) {
        debugPrint("DEBUG: Format tanggal salah pada jemaat: ${jemaat['namaLengkap']}");
      }
    }
  }

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
        elevation: 2,
      ),
      body: Column(
        children: [
          // SEARCH BAR
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              onChanged: _filterSearch,
              decoration: InputDecoration(
                hintText: "Cari nama jemaat...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // TAMPILAN LOADING / ERROR / DATA
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 15),
                        Text("Menghubungkan ke server..."),
                      ],
                    ),
                  )
                : _errorMessage.isNotEmpty && _allJemaat.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.info_outline, size: 50, color: Colors.grey),
                              const SizedBox(height: 10),
                              Text(_errorMessage, textAlign: TextAlign.center),
                              TextButton(onPressed: _loadJemaat, child: const Text("Coba Lagi")),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadJemaat,
                        child: ListView(
                          children: [
                            // Header Ultah
                            if (_ultahMingguIni.isNotEmpty)
                              _buildBirthdayCard(),

                            // List Jemaat
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _filteredJemaat.length,
                              itemBuilder: (context, index) {
                                final j = _filteredJemaat[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.indigo.shade100,
                                      child: Text(j['namaLengkap']?[0]?.toUpperCase() ?? "?"),
                                    ),
                                    title: Text(j['namaLengkap'] ?? "Tanpa Nama", style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text("${j['status'] ?? 'Jemaat'} • ${j['kelompok'] ?? '-'}"),
                                    trailing: user.isAdmin() 
                                        ? const Icon(Icons.edit_note, color: Colors.indigo) 
                                        : const Icon(Icons.arrow_forward_ios, size: 14),
                                    onTap: () {
                                      // Detail Jemaat
                                    },
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: user.isAdmin() 
          ? FloatingActionButton.extended(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text("Jemaat Baru"),
            )
          : null,
    );
  }

  Widget _buildBirthdayCard() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.orange.shade300, Colors.orange.shade600]),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(Icons.cake, color: Colors.white, size: 40),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Ultah Minggu Ini", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(_ultahMingguIni.join(", "), style: const TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}