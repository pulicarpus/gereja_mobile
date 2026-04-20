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
        // Mengambil SEMUA data gereja dari koleksi 'churches' secara real-time
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
              
              // Menarik field yang ada di Firestore masing-masing gereja
              String namaGereja = data['namaGereja'] ?? data['churchName'] ?? "Gereja Tanpa Nama"; 
              String namaGembala = data['namaGembala'] ?? "Belum ada data Gembala";
              String alamat = data['alamat'] ?? "Alamat belum diatur";
              String? fotoGembala = data['fotoGembalaUrl'];

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
                  title: Text(
                    namaGereja.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                        children: [
                          const Icon(Icons.location_on_outlined, size: 14, color: Colors.redAccent),
                          const SizedBox(width: 5),
                          Expanded(child: Text(alamat, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 2, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ],
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.indigo.shade50, shape: BoxShape.circle),
                    child: const Icon(Icons.chevron_right, color: Colors.indigo),
                  ),
                  onTap: () {
                     // Rencana ke depan: Kalau diklik bisa masuk ke detail lengkap gereja tersebut
                     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Profil lengkap $namaGereja akan segera hadir!")));
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