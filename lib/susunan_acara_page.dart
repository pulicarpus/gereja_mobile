import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_manager.dart';

class SusunanAcaraPage extends StatefulWidget {
  final String jadwalId;
  final String namaKegiatan;

  const SusunanAcaraPage({super.key, required this.jadwalId, required this.namaKegiatan});

  @override
  State<SusunanAcaraPage> createState() => _SusunanAcaraPageState();
}

class _SusunanAcaraPageState extends State<SusunanAcaraPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final UserManager _userManager = UserManager();
  
  // Simpan data di sini agar bisa diakses oleh FAB
  List<String> _currentUrutan = ["Belum diatur."];
  List<String> _currentLagu = ["Belum diatur."];

  void _showEditDialog(String field, List<String> currentData) {
    if (!_userManager.isAdmin()) return;

    final controller = TextEditingController(text: currentData.join("\n"));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit ${field == 'urutanAcara' ? 'Urutan Acara' : 'Daftar Lagu'}"),
        content: TextField(
          controller: controller,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: "Gunakan baris baru untuk setiap poin...",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () async {
              String? churchId = _userManager.getChurchIdForCurrentView();
              List<String> newData = controller.text.split("\n").where((s) => s.trim().isNotEmpty).toList();

              await _db.collection("churches").doc(churchId)
                  .collection("jadwal").doc(widget.jadwalId).update({
                field: newData,
              });

              if (mounted) Navigator.pop(context);
            },
            child: const Text("Simpan"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String? churchId = _userManager.getChurchIdForCurrentView();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.namaKegiatan),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.format_list_numbered), text: "Urutan Acara"),
              Tab(icon: Icon(Icons.music_note), text: "Daftar Lagu"),
            ],
            indicatorColor: Colors.white,
          ),
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: _db.collection("churches").doc(churchId)
              .collection("jadwal").doc(widget.jadwalId).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            
            var data = snapshot.data!.data() as Map<String, dynamic>?;
            
            // Update variabel state agar FAB bisa baca data terbaru
            _currentUrutan = List<String>.from(data?['urutanAcara'] ?? ["Belum diatur."]);
            _currentLagu = List<String>.from(data?['daftarLagu'] ?? ["Belum diatur."]);

            return TabBarView(
              children: [
                _buildListView(_currentUrutan),
                _buildListView(_currentLagu),
              ],
            );
          },
        ),
        floatingActionButton: _userManager.isAdmin() 
          ? Builder(
              builder: (context) => FloatingActionButton.extended(
                onPressed: () {
                  final index = DefaultTabController.of(context).index;
                  if (index == 0) {
                    _showEditDialog("urutanAcara", _currentUrutan);
                  } else {
                    _showEditDialog("daftarLagu", _currentLagu);
                  }
                },
                label: const Text("Edit Acara"),
                icon: const Icon(Icons.edit),
              ),
            )
          : null,
      ),
    );
  }

  Widget _buildListView(List<String> items) {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(color: Colors.indigo, shape: BoxShape.circle),
                child: Center(
                  child: Text("${index + 1}", 
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Text(items[index], 
                  style: const TextStyle(fontSize: 16, height: 1.4)),
              ),
            ],
          ),
        );
      },
    );
  }
}