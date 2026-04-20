import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

class DataGerejaDaerahPage extends StatelessWidget {
  final String namaDaerah; // 👈 MENERIMA KIRIMAN NAMA DAERAH

  const DataGerejaDaerahPage({super.key, required this.namaDaerah});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text("Gereja di $namaDaerah", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // 👇 FILTER SAKTI: HANYA AMBIL GEREJA YANG DAERAHNYA SAMA 👇
        stream: FirebaseFirestore.instance
            .collection('churches')
            .where('daerah', isEqualTo: namaDaerah == "Belum Diatur" ? null : namaDaerah)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            // Karena Firebase tidak bisa query null dengan == secara sempurna untuk field yang hilang, 
            // kita lakukan filter manual untuk yang "Belum Diatur" di bawah ini.
          }

          var docs = snapshot.data?.docs ?? [];

          // Filter manual khusus untuk gereja yang field 'daerah'-nya kosong/belum ada
          if (namaDaerah == "Belum Diatur") {
             docs = docs.where((doc) {
                var d = doc.data() as Map<String, dynamic>;
                return !d.containsKey('daerah') || d['daerah'] == null || d['daerah'].toString().trim().isEmpty;
             }).toList();
          }

          if (docs.isEmpty) {
             return const Center(child: Text("Tidak ada gereja di daerah ini."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data() as Map<String, dynamic>;
              
              String namaGereja = data['namaGereja'] ?? data['churchName'] ?? "Gereja Tanpa Nama"; 
              String namaGembala = data['namaGembala'] ?? "Belum ada data Gembala";
              String alamat = data['alamat'] ?? "Alamat belum diatur";
              String? fotoGembala = data['fotoGembalaUrl'];

              return Container(
                margin: const EdgeInsets.only(bottom: 15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
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