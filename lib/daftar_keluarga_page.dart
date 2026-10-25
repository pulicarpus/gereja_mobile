import 'family_actions.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_manager.dart';
import 'app_safety.dart';
import 'anggota_keluarga_page.dart';
import 'pilih_jemaat_page.dart'; // Memanggil halaman yang kita buat kemarin

class DaftarKeluargaPage extends StatefulWidget {
  const DaftarKeluargaPage({super.key});

  @override
  State<DaftarKeluargaPage> createState() => _DaftarKeluargaPageState();
}

class _DaftarKeluargaPageState extends State<DaftarKeluargaPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final UserManager _userManager = UserManager();
  String? _churchId;
  final _searchController = TextEditingController();
  String _query = '';
  Stream<QuerySnapshot>? _familiesStream;

  @override
  void initState() {
    super.initState();
    _churchId = _userManager.getChurchIdForCurrentView();
    if (_churchId != null) {
      _familiesStream = _db
          .collection('churches')
          .doc(_churchId)
          .collection('jemaat')
          .snapshots();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _saving = false;
  Future<void> _buatKeluargaBaru() async {
    if (_saving) return;
    if (_churchId == null) return;
    final selected = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const PilihJemaatPage()),
    );
    if (selected == null || !mounted) return;

    final id = selected['id']?.toString();
    final nama = (selected['namaLengkap'] ?? 'jemaat ini').toString();
    if (id == null || id.isEmpty) return;

    final currentFamily = (selected['idKepalaKeluarga'] ?? '').toString();
    if (currentFamily.isNotEmpty && currentFamily != id) {
      final lanjut =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Jemaat Sudah Terikat Keluarga"),
              content: Text(
                "$nama sudah menjadi anggota keluarga lain. Jadikan sebagai Kepala Keluarga baru?",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Batal"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("Lanjutkan"),
                ),
              ],
            ),
          ) ??
          false;
      if (!lanjut) return;
    }

    if (!mounted || _saving) return;
    _saving = true;
    try {
      final access = await ChurchWriteAccess.check(_churchId!);
      final ref = _db
          .collection('churches')
          .doc(_churchId)
          .collection('jemaat')
          .doc(id);
      await _db
          .runTransaction((tx) async {
            await access.inTransaction(tx);
            final fresh = await tx.get(ref);
            if (!fresh.exists ||
                legacyText(fresh.data()?['idKepalaKeluarga']) !=
                    currentFamily ||
                fresh.data()?['statusKeluarga'] != selected['statusKeluarga']) {
              throw StateError(
                'Relasi keluarga sudah berubah. Pilih ulang jemaat.',
              );
            }
            final oldHead = currentFamily.isNotEmpty && currentFamily != id
                ? await tx.get(ref.parent.doc(currentFamily))
                : null;
            access.assertCurrent();
            if (oldHead?.exists == true)
              tx.update(oldHead!.reference, {
                'familyRevision': FieldValue.increment(1),
              });
            tx.update(ref, {
              'idKepalaKeluarga': id,
              'statusKeluarga': 'Kepala Keluarga',
            });
          })
          .timeout(const Duration(seconds: 20));
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Keluarga $nama berhasil dibuat.")),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Gagal membuat keluarga: $e")));
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_churchId == null)
      return const Scaffold(
        body: Center(child: Text("Data gereja tidak valid")),
      );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          "Daftar Keluarga",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Cari kepala keluarga atau anggota',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus pencarian',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _familiesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.indigo),
                  );
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.family_restroom,
                          size: 60,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          "Belum ada data keluarga.",
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  );
                }

                // Urutkan berdasarkan Abjad Nama Keluarga
                var listKeluarga = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['statusKeluarga'] == 'Kepala Keluarga' &&
                      data['status'] != 'Meninggal';
                }).toList();
                if (listKeluarga.isEmpty) {
                  return const Center(
                    child: Text(
                      "Belum ada keluarga aktif.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                // Search members as well, but show each matching family only once.
                if (_query.isNotEmpty) {
                  final matchingHeads = <String>{};
                  for (final member in snapshot.data!.docs) {
                    final data = member.data() as Map<String, dynamic>;
                    final name = legacyText(data['namaLengkap']).toLowerCase();
                    if (name.contains(_query)) {
                      matchingHeads.add(
                        data['statusKeluarga'] == 'Kepala Keluarga'
                            ? member.id
                            : legacyText(data['idKepalaKeluarga']),
                      );
                    }
                  }
                  listKeluarga = listKeluarga
                      .where((doc) => matchingHeads.contains(doc.id))
                      .toList();
                  if (listKeluarga.isEmpty) {
                    return const Center(
                      child: Text('Keluarga tidak ditemukan.'),
                    );
                  }
                }
                listKeluarga.sort((a, b) {
                  var dataA = a.data() as Map<String, dynamic>;
                  var dataB = b.data() as Map<String, dynamic>;
                  String namaA = dataA['namaLengkap'] ?? "";
                  String namaB = dataB['namaLengkap'] ?? "";
                  return namaA.toLowerCase().compareTo(namaB.toLowerCase());
                });

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: listKeluarga.length,
                  itemBuilder: (context, index) {
                    var doc = listKeluarga[index];
                    var data = doc.data() as Map<String, dynamic>;

                    String nama = data['namaLengkap'] ?? "Tanpa Nama";
                    String alamat = data['alamat'] ?? "Alamat belum diisi";

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        leading: CircleAvatar(
                          radius: 25,
                          backgroundColor: Colors.indigo.shade100,
                          child: const Icon(
                            Icons.family_restroom,
                            color: Colors.indigo,
                          ),
                        ),
                        title: Text(
                          "Kel. $nama",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          alamat,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        trailing: _userManager.isAdmin()
                            ? PopupMenuButton<String>(
                                tooltip: 'Tindakan keluarga',
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'cancelHead',
                                    child: Text(
                                      'Batalkan jadi kepala keluarga',
                                    ),
                                  ),
                                ],
                                onSelected: (_) => confirmCancelFamilyHead(
                                  context,
                                  _churchId!,
                                  doc.id,
                                  nama,
                                ),
                              )
                            : const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 16,
                                color: Colors.grey,
                              ),
                        onTap: () {
                          // 👇 LOMPAT KE HALAMAN ANGGOTA KELUARGA 👇
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AnggotaKeluargaPage(
                                idKepalaKeluarga: doc
                                    .id, // ID dia sebagai patokan pencarian anggota
                                namaKepalaKeluarga: nama,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _userManager.isAdmin()
          ? FloatingActionButton.extended(
              onPressed: _buatKeluargaBaru,
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_home_work),
              label: const Text("Buat Keluarga"),
            )
          : null,
    );
  }
}
