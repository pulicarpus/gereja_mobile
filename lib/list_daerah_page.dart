import 'region_actions.dart';
import 'user_manager.dart';
import 'region_names.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'menu_daerah_page.dart'; // 👈 IMPORT MENU DAERAHNYA

class ListDaerahPage extends StatelessWidget {
  const ListDaerahPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Pilih Wilayah / Daerah", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('churches').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Belum ada data."));
          }

          final regions = groupChurchRegions(snapshot.data!.docs.map(
            (doc) => doc.data() as Map<String, dynamic>));

          if (regions.isEmpty) return const Center(child: Text('Belum ada daerah aktif.'));
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: regions.length,
            itemBuilder: (context, index) {
              String namaDaerah = regions[index].name;
              int jumlahGereja = regions[index].count;

              return Container(
                margin: const EdgeInsets.only(bottom: 15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
                  border: Border.all(color: Colors.indigo.shade50)
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  leading: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.orange.shade100, shape: BoxShape.circle),
                    child: const Icon(Icons.map, color: Colors.deepOrange),
                  ),
                  title: Text(
                    regions[index].displayName.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text("Total: $jumlahGereja Gereja Lokal", style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.w600)),
                  ),
                  trailing: UserManager().isSuperAdmin()
                    ? PopupMenuButton<String>(
                      tooltip: 'Kelola daerah',
                      onSelected: (action) => manageRegion(context, namaDaerah,
                        regions[index].displayName, delete: action == 'delete'),
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit Nama Daerah')),
                        PopupMenuItem(value: 'delete', child: Text('Hapus Daerah')),
                      ],
                    ) : const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    // 👇 SEKARANG MENGARAH KE KANTOR / MENU DAERAH 👇
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => MenuDaerahPage(namaDaerah: namaDaerah)
                    ));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}