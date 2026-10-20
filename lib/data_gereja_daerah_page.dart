import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'region_label.dart';
import 'region_names.dart';
import 'app_safety.dart';
import 'church_pastors.dart';
import 'pastor_profile_page.dart';
import 'pengurus_widgets.dart';
import 'detail_gereja_page.dart';

class DataGerejaDaerahPage extends StatelessWidget {
  final String namaDaerah;
  const DataGerejaDaerahPage({super.key, required this.namaDaerah});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FA),
    appBar: AppBar(
      title: RegionLabel(
        area: namaDaerah,
        prefix: 'Gereja di ',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      backgroundColor: Colors.indigo.shade900,
      foregroundColor: Colors.white,
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('churches').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(child: pengurusMessage(pengurusError(snapshot.error!)));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs
            .where(
              (doc) =>
                  doc.data()['isArchived'] != true &&
                  regionNameKey(doc.data()['daerah']) ==
                      regionNameKey(namaDaerah),
            )
            .toList();
        if (docs.isEmpty)
          return const Center(child: Text('Tidak ada gereja di daerah ini.'));
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final rawName = legacyText(
              data['namaGereja'] ?? data['churchName'],
            ).trim();
            final name = rawName.isEmpty ? 'Gereja Tanpa Nama' : rawName;
            final rawAddress = legacyText(data['alamat']).trim();
            return RegionChurchCard(
              churchId: doc.id,
              churchName: name,
              address: rawAddress.isEmpty ? 'Alamat belum diatur' : rawAddress,
              pastors: churchPastors(data),
              onStatistics: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      DetailGerejaPage(churchId: doc.id, namaGereja: name),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class RegionChurchCard extends StatelessWidget {
  final String churchId, churchName, address;
  final List<ChurchPastor> pastors;
  final VoidCallback onStatistics;
  const RegionChurchCard({
    super.key,
    required this.churchId,
    required this.churchName,
    required this.address,
    required this.pastors,
    required this.onStatistics,
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.church, color: Colors.indigo, size: 28),
            title: Text(
              churchName.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(address, style: const TextStyle(color: Colors.grey)),
            trailing: IconButton(
              tooltip: 'Statistik $churchName',
              onPressed: onStatistics,
              icon: const Icon(Icons.analytics_outlined, color: Colors.indigo),
            ),
          ),
          if (pastors.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Belum ada data gembala.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          for (final pastor in pastors)
            ListTile(
              leading: ChurchPastorAvatar(
                pastor: pastor,
                churchId: churchId,
                radius: 24,
              ),
              title: Text(
                pastor.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Gembala Sidang'),
              trailing: const Icon(Icons.chevron_right, color: Colors.indigo),
              onTap: () =>
                  openPastorProfile(context, pastor, churchId, churchName),
            ),
        ],
      ),
    ),
  );
}
