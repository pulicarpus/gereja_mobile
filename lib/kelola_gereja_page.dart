import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; 

import 'add_edit_gereja_page.dart'; 
import 'user_manager.dart'; 

class KelolaGerejaPage extends StatelessWidget {
  const KelolaGerejaPage({super.key});

  @override
  Widget build(BuildContext context) {
    bool isSuperAdmin = UserManager().isSuperAdmin();

    if (!isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text("Akses Ditolak"), backgroundColor: Colors.red[900]),
        body: const Center(child: Text("Hanya Superadmin yang diizinkan masuk.")),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100], 
      appBar: AppBar(
        title: const Text("Kelola & Pilih Gereja"),
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

          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("Belum ada data gereja.\nTekan + untuk menambah.", textAlign: TextAlign.center),
            );
          }

          var gerejaList = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: gerejaList.length,
            itemBuilder: (context, index) {
              var data = gerejaList[index].data() as Map<String, dynamic>;
              var docId = gerejaList[index].id;
              
              String namaGereja = data['nama'] ?? data['churchName'] ?? "Gereja Tanpa Nama";
              String alamatGereja = data['alamat'] ?? "Alamat belum diisi";
              String kodeUndangan = data['kodeUndangan'] ?? "-";
              // 👇 DETEKTOR DAERAH DITAMBAHKAN DI SINI 👇
              String namaDaerah = data['daerah'] ?? "Belum Diatur";

              bool isActive = UserManager().activeChurchId == docId;

              return Card(
                elevation: isActive ? 4 : 1, 
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: isActive ? Colors.indigo : Colors.transparent, width: 2),
                ),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                      leading: CircleAvatar(
                        backgroundColor: isActive ? Colors.indigo : Colors.indigo[50],
                        child: Icon(Icons.church, color: isActive ? Colors.white : Colors.indigo),
                      ),
                      title: Text(
                        namaGereja, 
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: isActive ? Colors.indigo[900] : Colors.black87)
                      ),
                      // 👇 MENAMPILKAN LABEL DAERAH DI BAWAH NAMA GEREJA 👇
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(5)
                            ),
                            child: Text(
                              "Daerah: $namaDaerah", 
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade900)
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(alamatGereja, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_note, color: Colors.blueGrey, size: 28),
                        tooltip: "Edit Info Gereja",
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => AddEditGerejaPage(gerejaId: docId)),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.indigo[50] : Colors.transparent,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15))
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(kodeUndangan, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 15)),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: kodeUndangan));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Kode $kodeUndangan disalin!"), backgroundColor: Colors.green[700]),
                                  );
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(4.0),
                                  child: Icon(Icons.copy, size: 18, color: Colors.indigo),
                                ),
                              ),
                            ],
                          ),
                          
                          ElevatedButton.icon(
                            onPressed: isActive ? null : () async {
                              await UserManager().enterChurchContext(docId, namaGereja);
                              
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Memasuki sistem: $namaGereja", style: const TextStyle(fontWeight: FontWeight.bold)),
                                    backgroundColor: Colors.indigo[900],
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                                Navigator.pop(context);
                              }
                            },
                            icon: Icon(isActive ? Icons.check_circle : Icons.login, size: 18),
                            label: Text(isActive ? "Sedang Aktif" : "Kelola Data"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isActive ? Colors.green : Colors.indigo[900],
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          )
                        ],
                      ),
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        tooltip: "Tambah Gereja Baru",
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddEditGerejaPage()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}