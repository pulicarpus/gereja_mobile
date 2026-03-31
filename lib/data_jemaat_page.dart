import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_chart/fl_chart.dart'; // Library Grafik
import 'user_manager.dart';
import 'add_edit_jemaat_page.dart';

class DataJemaatPage extends StatefulWidget {
  final String? filterKategorial;
  const DataJemaatPage({super.key, this.filterKategorial});

  @override
  State<DataJemaatPage> createState() => _DataJemaatPageState();
}

class _DataJemaatPageState extends State<DataJemaatPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final UserManager _userManager = UserManager();
  
  List<Map<String, dynamic>> _allJemaat = [];
  List<Map<String, dynamic>> _filteredJemaat = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadJemaat();
  }

  Future<void> _loadJemaat() async {
    String? churchId = _userManager.getChurchIdForCurrentView();
    if (churchId == null) return;
    try {
      Query query = _db.collection("churches").doc(churchId).collection("jemaat");
      if (widget.filterKategorial != null) {
        query = query.where("kelompok", isEqualTo: widget.filterKategorial);
      }
      final snapshot = await query.get();
      final tempData = snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _allJemaat = tempData;
          _filteredJemaat = tempData;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- FITUR SEARCH (KEMBALI HADIR!) ---
  void _filterSearch(String query) {
    setState(() {
      _filteredJemaat = _allJemaat
          .where((j) => j['namaLengkap']!.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  // --- FITUR STATISTIK GRAFIK ---
  void _showStatistikGrafik() {
    Map<String, int> stats = {};
    for (var j in _allJemaat) {
      String k = j['kelompok'] ?? "Lainnya";
      stats[k] = (stats[k] ?? 0) + 1;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Statistik Kelompok"),
        content: SizedBox(
          height: 350,
          width: double.maxFinite,
          child: Column(
            children: [
              Expanded(
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: stats.values.isEmpty ? 10 : (stats.values.reduce((a, b) => a > b ? a : b) + 2).toDouble(),
                    barGroups: stats.entries.toList().asMap().entries.map((entry) {
                      return BarChartGroupData(
                        x: entry.key,
                        barRods: [
                          BarChartRodData(
                            toY: entry.value.value.toDouble(),
                            color: Colors.indigoAccent,
                            width: 18,
                            borderRadius: BorderRadius.circular(4),
                          )
                        ],
                      );
                    }).toList(),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            String label = stats.keys.elementAt(value.toInt());
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(label.substring(0, 3), style: const TextStyle(fontSize: 10)),
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text("Total Jemaat: ${_allJemaat.length}", style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tutup"))],
      ),
    );
  }

  // --- DETAIL INFO & KELUARGA (LOGIKA TETAP SAMA) ---
  void _showDetailJemaat(Map<String, dynamic> j) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundImage: j['fotoProfil'] != null ? NetworkImage(j['fotoProfil']) : null,
                child: j['fotoProfil'] == null ? Text(j['namaLengkap']?[0] ?? "?", style: const TextStyle(fontSize: 30)) : null,
              ),
              const SizedBox(height: 10),
              Text(j['namaLengkap'] ?? "-", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text("${j['statusKeluarga']} • ${j['kelompok']}"),
              const Divider(height: 30),
              _buildTile(Icons.phone, "HP", j['nomorTelepon'] ?? "-"),
              _buildTile(Icons.location_on, "Alamat", j['alamat'] ?? "-"),
              _buildTile(Icons.cake, "Tgl Lahir", j['tanggalLahir'] ?? "-"),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showKeluarga(j['idKepalaKeluarga'], j['namaLengkap']),
                      icon: const Icon(Icons.people),
                      label: const Text("Keluarga"),
                    ),
                  ),
                  if (j['nomorTelepon'] != null && j['nomorTelepon'] != "-") ...[
                    const SizedBox(width: 10),
                    IconButton.filled(onPressed: () => launchUrl(Uri.parse("tel:${j['nomorTelepon']}")), icon: const Icon(Icons.call)),
                  ]
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTile(IconData icon, String label, String val) => ListTile(leading: Icon(icon), title: Text(val), subtitle: Text(label), dense: true);

  void _showKeluarga(String? idKK, String? nama) {
    if (idKK == null || idKK.isEmpty) return;
    final keluarga = _allJemaat.where((j) => j['idKepalaKeluarga'] == idKK).toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Keluarga $nama"),
        content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: keluarga.length, itemBuilder: (c, i) => ListTile(title: Text(keluarga[i]['namaLengkap']), subtitle: Text(keluarga[i]['statusKeluarga'])))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tutup"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching 
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(hintText: "Cari nama jemaat...", border: InputBorder.none),
              onChanged: _filterSearch,
            )
          : Text(widget.filterKategorial ?? "Data Jemaat"),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _filteredJemaat = _allJemaat;
                }
              });
            },
          ),
          IconButton(onPressed: _showStatistikGrafik, icon: const Icon(Icons.bar_chart_rounded)),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            itemCount: _filteredJemaat.length,
            itemBuilder: (context, index) {
              final j = _filteredJemaat[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: j['fotoProfil'] != null ? NetworkImage(j['fotoProfil']) : null,
                    child: j['fotoProfil'] == null ? Text(j['namaLengkap']?[0] ?? "?") : null,
                  ),
                  title: Text(j['namaLengkap'] ?? "-", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${j['statusKeluarga']} • ${j['kelompok']}"),
                  onTap: () => _showDetailJemaat(j),
                  onLongPress: () { if (_userManager.isAdmin()) _showAksiAdmin(j); },
                ),
              );
            },
          ),
      floatingActionButton: _userManager.isAdmin() 
        ? FloatingActionButton.extended(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AddEditJemaatPage())).then((v) => _loadJemaat()),
            label: const Text("Tambah"), icon: const Icon(Icons.add),
          ) : null,
    );
  }

  void _showAksiAdmin(Map<String, dynamic> j) {
    showModalBottomSheet(context: context, builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.edit), title: const Text("Edit"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => AddEditJemaatPage(jemaatData: j))).then((v) => _loadJemaat()); }),
      ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("Hapus"), onTap: () { Navigator.pop(context); _db.collection("churches").doc(_userManager.getChurchIdForCurrentView()).collection("jemaat").doc(j['id']).delete(); _loadJemaat(); }),
    ]));
  }
}