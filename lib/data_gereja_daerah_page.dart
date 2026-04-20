import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

class DataGerejaDaerahPage extends StatelessWidget {
  const DataGerejaDaerahPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Data Gereja & Pengerja", style: TextStyle(fontWeight: FontWeight.bold)),
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
            return const Center(child: Text("Belum ada data gereja yang terdaftar."));
          }

          var docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data() as Map<String, dynamic>;
              
              String namaGereja = data['namaGereja'] ?? data['churchName'] ?? "Gereja Tanpa Nama"; 
              String namaGembala = data['namaGembala'] ?? "Belum ada data Gembala";
              String alamat = data['alamat'] ?? "Alamat belum diatur";
              String? fotoGembala = data['fotoGembalaUrl'];
              
              // 👇 INI DIA PENAMBAHAN LABEL DAERAHNYA 👇
              String namaDaerah = data['daerah'] ?? "Daerah Belum Diatur";

              return Container(
                margin: const EdgeInsets.only(bottom: 15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(15),
                  leading: CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.indigo.shade50,
                    backgroundImage: fotoGembala != null ? CachedNetworkImageProvider(fotoGembala) : null,
                    child: fotoGembala == null ? const Icon(Icons.person, color: Colors.indigo) : null,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          namaGereja.toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      // BADGE DAERAH
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100, 
                          borderRadius: BorderRadius.circular(8)
                        ),
                        child: Text(
                          "Wilayah/Daerah: $namaDaerah", 
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade900)
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 14, color: Colors.indigo),
                          const SizedBox(width: 5),
                          Expanded(child: Text("Pdt/Ev: $namaGembala", style: const TextStyle(fontSize: 13))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.location_on_outlined, size: 14, color: Colors.redAccent),
                          ),
                          const SizedBox(width: 5),
                          Expanded(child: Text(alamat, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 2, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}