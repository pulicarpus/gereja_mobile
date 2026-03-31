import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_chart/fl_chart.dart'; 
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

  final List<Color> _colors = [
    Colors.blueAccent, Colors.redAccent, Colors.greenAccent, 
    Colors.orangeAccent, Colors.purpleAccent, Colors.tealAccent
  ];

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

      setState(() {
        _allJemaat = tempData;
        _filteredJemaat = tempData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _filterSearch(String query) {
    setState(() {
      _filteredJemaat = _allJemaat
          .where((j) => j['namaLengkap']!.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  // --- MODAL DASHBOARD STATISTIK LENGKAP ---
  void _showStatistikDashboard() {
    Map<String, int> statsKelompok = {};
    int pria = 0, wanita = 0;
    int sudahBaptis = 0, belumBaptis = 0;

    for (var j in _allJemaat) {
      // 1. Hitung Kelompok (Bar)
      String k = j['kelompok'] ?? "Lainnya";
      statsKelompok[k] = (statsKelompok[k] ?? 0) + 1;
      
      // 2. Hitung Gender (Pie)
      if (j['jenisKelamin'] == "Pria") pria++; else wanita++;

      // 3. Hitung Baptis (Pie)
      if (j['statusBaptis'] == "Sudah") sudahBaptis++; else belumBaptis++;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Dashboard Statistik Jemaat", style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Total Jemaat: ${_allJemaat.length}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                
                // --- BAGIAN 1: GRAFIK BATANG (KELOMPOK) ---
                const Text("Berdasarkan Kelompok", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      maxY: (statsKelompok.values.isEmpty ? 10 : statsKelompok.values.reduce((a, b) => a > b ? a : b) + 5).toDouble(),
                      barGroups: statsKelompok.entries.toList().asMap().entries.map((e) => BarChartGroupData(
                        x: e.key,
                        barRods: [BarChartRodData(toY: e.value.value.toDouble(), color: _colors[e.key % _colors.length], width: 16)],
                        showingTooltipIndicators: [0],
                      )).toList(),
                      titlesData: const FlTitlesData(show: false),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => Colors.transparent,
                          getTooltipItem: (g, gi, r, ri) => BarTooltipItem(r.toY.round().toString(), const TextStyle(fontWeight: FontWeight.bold))
                        ),
                      ),
                    ),
                  ),
                ),
                _buildLegend(statsKelompok.keys.toList()),
                
                const Divider(height: 40),

                // --- BAGIAN 2: GRAFIK PIE (GENDER & BAPTIS) ---
                Row(
                  children: [
                    // Pie Jenis Kelamin
                    Expanded(
                      child: Column(
                        children: [
                          const Text("Gender", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          SizedBox(
                            height: 120,
                            child: PieChart(PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 20,
                              sections: [
                                PieChartSectionData(value: pria.toDouble(), title: '$pria', color: Colors.blue, radius: 40, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                PieChartSectionData(value: wanita.toDouble(), title: '$wanita', color: Colors.pink, radius: 40, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            )),
                          ),
                          const Text("Pria(B) / Wnt(P)", style: TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                    // Pie Baptis
                    Expanded(
                      child: Column(
                        children: [
                          const Text("Baptisan", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          SizedBox(
                            height: 120,
                            child: PieChart(PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 20,
                              sections: [
                                PieChartSectionData(value: sudahBaptis.toDouble(), title: '$sudahBaptis', color: Colors.green, radius: 40, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                PieChartSectionData(value: belumBaptis.toDouble(), title: '$belumBaptis', color: Colors.grey, radius: 40, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            )),
                          ),
                          const Text("Sdh(H) / Blm(A)", style: TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tutup"))],
      ),
    );
  }

  Widget _buildLegend(List<String> keys) {
    return Wrap(
      spacing: 10,
      children: keys.asMap().entries.map((e) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, color: _colors[e.key % _colors.length]),
          const SizedBox(width: 4),
          Text(e.value, style: const TextStyle(fontSize: 10)),
        ],
      )).toList(),
    );
  }

  // --- DETAIL & LIST (TETAP SAMA) ---
  void _showDetailJemaat(Map<String, dynamic> j) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8, expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController, padding: const EdgeInsets.all(20),
          child: Column(children: [
            CircleAvatar(radius: 50, backgroundImage: (j['fotoProfil'] != null && j['fotoProfil'] != "") ? NetworkImage(j['fotoProfil']) : null, child: (j['fotoProfil'] == null || j['fotoProfil'] == "") ? Text(j['namaLengkap']?[0] ?? "?", style: const TextStyle(fontSize: 30)) : null),
            const SizedBox(height: 10),
            Text(j['namaLengkap'] ?? "-", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text("${j['statusKeluarga']} • ${j['kelompok']}"),
            const Divider(height: 30),
            _buildTile(Icons.wc, "Jenis Kelamin", j['jenisKelamin'] ?? "-"),
            _buildTile(Icons.water_drop, "Baptis", j['statusBaptis'] ?? "-"),
            _buildTile(Icons.phone, "HP", j['nomorTelepon'] ?? "-"),
            _buildTile(Icons.location_on, "Alamat", j['alamat'] ?? "-"),
            const SizedBox(height: 20),
            ElevatedButton.icon(onPressed: () => _showKeluarga(j['idKepalaKeluarga'], j['namaLengkap']), icon: const Icon(Icons.people), label: const Text("Lihat Keluarga"), style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45))),
          ]),
        ),
      ),
    );
  }

  Widget _buildTile(IconData icon, String label, String val) => ListTile(leading: Icon(icon, color: Colors.indigo), title: Text(val), subtitle: Text(label), dense: true);

  void _showKeluarga(String? idKK, String? nama) {
    if (idKK == null || idKK.isEmpty) return;
    final keluarga = _allJemaat.where((j) => j['idKepalaKeluarga'] == idKK).toList();
    showDialog(context: context, builder: (c) => AlertDialog(title: Text("Keluarga $nama"), content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: keluarga.length, itemBuilder: (c, i) => ListTile(title: Text(keluarga[i]['namaLengkap']), subtitle: Text(keluarga[i]['statusKeluarga'])))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tutup"))]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching ? TextField(controller: _searchController, autofocus: true, decoration: const InputDecoration(hintText: "Cari...", border: InputBorder.none), onChanged: _filterSearch) : Text(widget.filterKategorial ?? "Data Jemaat"),
        actions: [
          IconButton(icon: Icon(_isSearching ? Icons.close : Icons.search), onPressed: () => setState(() { _isSearching = !_isSearching; if (!_isSearching) { _searchController.clear(); _filteredJemaat = _allJemaat; } })),
          IconButton(onPressed: _showStatistikDashboard, icon: const Icon(Icons.dashboard_customize)),
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(itemCount: _filteredJemaat.length, itemBuilder: (context, index) {
        final j = _filteredJemaat[index];
        return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: ListTile(leading: CircleAvatar(backgroundImage: (j['fotoProfil'] != null && j['fotoProfil'] != "") ? NetworkImage(j['fotoProfil']) : null, child: (j['fotoProfil'] == null || j['fotoProfil'] == "") ? Text(j['namaLengkap']?[0] ?? "?") : null), title: Text(j['namaLengkap'] ?? "-", style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text("${j['statusKeluarga']} • ${j['kelompok']}"), onTap: () => _showDetailJemaat(j), onLongPress: () { if (_userManager.isAdmin()) _showAksiAdmin(j); }));
      }),
      floatingActionButton: _userManager.isAdmin() ? FloatingActionButton.extended(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AddEditJemaatPage())).then((v) => _loadJemaat()), label: const Text("Tambah"), icon: const Icon(Icons.add)) : null,
    );
  }

  void _showAksiAdmin(Map<String, dynamic> j) {
    showModalBottomSheet(context: context, builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.edit), title: const Text("Edit"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => AddEditJemaatPage(jemaatData: j))).then((v) => _loadJemaat()); }),
      ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("Hapus"), onTap: () { Navigator.pop(context); _db.collection("churches").doc(_userManager.getChurchIdForCurrentView()).collection("jemaat").doc(j['id']).delete(); _loadJemaat(); }),
    ]));
  }
}