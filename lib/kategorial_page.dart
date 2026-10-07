import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'kategorial_config.dart';
import 'sub_kategorial_page.dart';
import 'user_manager.dart';

class KategorialPage extends StatefulWidget {
  const KategorialPage({super.key});

  @override
  State<KategorialPage> createState() => _KategorialPageState();
}

class _KategorialPageState extends State<KategorialPage> {
  bool _refreshingIdentity = false;

  @override
  void initState() {
    super.initState();
    _refreshKategorialIdentity();
  }

  Future<void> _refreshKategorialIdentity() async {
    if (_refreshingIdentity) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _refreshingIdentity = true;
    try {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(currentUser.uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      if (!doc.exists) return;

      final data = doc.data() ?? <String, dynamic>{};
      final rawKelompok = data['kelompok']?.toString().trim() ?? "";
      var kelompok = rawKelompok.isEmpty ? "Umum" : rawKelompok;
      var isPengurus = data['isPengurus'] == true && data['isBlocked'] != true;

      final jemaatId = data['jemaatId']?.toString().trim() ?? "";
      final registeredChurchId =
          data['churchId']?.toString().trim() ?? "";

      if (jemaatId.isNotEmpty && registeredChurchId.isNotEmpty) {
        try {
          final jemaatDoc = await FirebaseFirestore.instance
              .collection("churches")
              .doc(registeredChurchId)
              .collection("jemaat")
              .doc(jemaatId)
              .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
          if (jemaatDoc.exists && jemaatDoc.data()?['uid']?.toString() == currentUser.uid) {
            final jemaatKelompok = KategorialConfig.canonicalJemaat(
              jemaatDoc.data()?['kelompok'],
            );
            if (!KategorialConfig.same(kelompok, jemaatKelompok)) {
              kelompok = jemaatKelompok;
              isPengurus = false;
            }
          } else {
            isPengurus = false;
          }
        } catch (e) {
          isPengurus = false;
          debugPrint("Gagal sinkron kelompok buku induk: $e");
        }
      }

      if (!mounted || FirebaseAuth.instance.currentUser?.uid != currentUser.uid ||
          UserManager().userId != currentUser.uid) return;
      final manager = UserManager();
      await manager.updateKategorialContext(
        kelompok,
        pengurus: isPengurus,
      );
      OneSignal.User.addTagWithKey("kelompok", kelompok);

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Gagal refresh identitas kategorial: $e");
    } finally {
      _refreshingIdentity = false;
    }
  }

  List<String> _orderedCategories() {
    final own = KategorialConfig.canonicalPelayanan(UserManager().userKomisi);
    final categories = List<String>.from(KategorialConfig.pelayanan);
    if (own != null) {
      categories
        ..remove(own)
        ..insert(0, own);
    }
    return categories;
  }

  ({IconData icon, Color color}) _visual(String name) {
    switch (name) {
      case KategorialConfig.sekolahMinggu:
        return (icon: Icons.child_care, color: Colors.orange);
      case KategorialConfig.amki:
        return (icon: Icons.group, color: Colors.blue);
      case KategorialConfig.perkawan:
        return (icon: Icons.woman, color: Colors.pink);
      case KategorialConfig.perkaria:
        return (icon: Icons.man, color: Colors.indigo);
      default:
        return (icon: Icons.groups, color: Colors.teal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final own = KategorialConfig.canonicalPelayanan(UserManager().userKomisi);
    final categories = _orderedCategories();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Kategorial & Komisi"),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: "Perbarui keanggotaan",
            onPressed: _refreshKategorialIdentity,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshKategorialIdentity,
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: categories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 15,
            mainAxisSpacing: 15,
            childAspectRatio: 1.0,
          ),
          itemBuilder: (context, index) {
            final name = categories[index];
            final visual = _visual(name);
            return _buildMenuCard(
              context,
              name,
              visual.icon,
              visual.color,
              isMine: own == name,
            );
          },
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context,
    String nama,
    IconData icon,
    Color color, {
    required bool isMine,
  }) {
    return Card(
      elevation: isMine ? 5 : 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: isMine
            ? BorderSide(color: color.withOpacity(0.6), width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => _bukaSub(context, nama),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isMine)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "KATEGORI SAYA",
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                nama,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _bukaSub(BuildContext context, String nama) {
    final canonical = KategorialConfig.canonicalPelayanan(nama);
    if (canonical == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubKategorialPage(namaKomisi: canonical),
      ),
    );
  }
}

