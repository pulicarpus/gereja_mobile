import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; 
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'dart:convert'; 

import 'user_manager.dart';
import 'kategorial_config.dart'; 
import 'add_edit_jadwal_page.dart';
import 'susunan_acara_page.dart';
import 'secrets.dart'; 

class JadwalPage extends StatefulWidget {
  final String? filterKategorial;
  const JadwalPage({super.key, this.filterKategorial});

  @override
  State<JadwalPage> createState() => _JadwalPageState();
}

class _JadwalPageState extends State<JadwalPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? churchId;
  
  bool _showRiwayat = false;

  bool _canManageCategory(String? category) {
    final user = UserManager();
    if (user.isAdmin()) return true;
    final kategori = category?.trim();
    return kategori != null &&
        kategori.isNotEmpty &&
        user.isPengurus &&
        KategorialConfig.same(user.userKomisi, kategori);
  }

  bool get canEdit {
    final currentChurch = UserManager().getChurchIdForCurrentView();
    return currentChurch != null &&
        currentChurch == churchId &&
        _canManageCategory(widget.filterKategorial);
  }

  bool _sameCategory(dynamic raw, String? expected) {
    final exp = expected?.trim();
    if (exp == null || exp.isEmpty) {
      final value = raw?.toString().trim() ?? "";
      return value.isEmpty ||
          KategorialConfig.same(value, "Umum");
    }
    return KategorialConfig.same(raw, exp);
  }

  @override
  void initState() {
    super.initState();
    final userManager = UserManager();
    churchId = userManager.getChurchIdForCurrentView();
    

  }

  DateTime? _dateFromData(Map<String, dynamic> data) {
    final raw = data['tanggal'];
    if (raw is Timestamp) return raw.toDate();
    final waktu = data['waktu']?.toString().trim();
    if (waktu == null || waktu.isEmpty) return null;
    try {
      return DateFormat("yyyy-MM-dd HH:mm").parse(waktu);
    } catch (_) {
      return null;
    }
  }

  String _formatTanggal(Map<String, dynamic> data) {
    final dt = _dateFromData(data);
    if (dt != null) {
      return DateFormat("EEEE, d MMMM yyyy • HH:mm", "id_ID").format(dt);
    }
    final fallback = data['waktu']?.toString().trim();
    return (fallback == null || fallback.isEmpty) ? "-" : fallback;
  }

  String? _labelHari(Map<String, dynamic> data) {
    final dt = _dateFromData(data);
    if (dt == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return "HARI INI";
    if (diff == 1) return "BESOK";
    return null;
  }

  Future<bool> _sendPengumumanNotification(String isiPengumuman) async {
    try {
      if (churchId == null || churchId!.isEmpty) return false;
      Map<String, dynamic> payload = {
        "app_id": "a9ff250a-56ef-413d-b825-67288008d614", 
        "filters": [
          {"field": "tag", "key": "active_church", "relation": "=", "value": churchId},
          if (widget.filterKategorial != null &&
              widget.filterKategorial!.trim().isNotEmpty) ...[
            {"operator": "AND"},
            {
              "field": "tag",
              "key": "kelompok",
              "relation": "=",
              "value": widget.filterKategorial!.trim(),
            }
          ]
        ], 
        "headings": {"en": "📢 Pengumuman Gereja!"},
        "contents": {"en": isiPengumuman},
        "data": {
          "type": "jadwal",
          "kategorial": widget.filterKategorial 
        }
      };

      final response = await http.post(
        Uri.parse("https://onesignal.com/api/v1/notifications"),
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Authorization": "Basic $osRestKeySecret"
        },
        body: jsonEncode(payload),
      );
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      debugPrint(ok ? "Notif pengumuman berhasil dikirim." : "Notif pengumuman ditolak: ${response.statusCode}");
      return ok;
    } catch (e) {
      debugPrint("Error kirim notif pengumuman: $e");
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (churchId == null) return const Scaffold(body: Center(child: Text("ID Gereja Kosong")));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(widget.filterKategorial ?? "Jadwal Ibadah", style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900], 
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('churches').doc(churchId).collection('jadwal')
            .orderBy('tanggal', descending: false).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.indigo));
          }
          
          if (snapshot.hasError) {
             return const Center(child: Text("Terjadi kesalahan koneksi."));
          }
          
          final docs = snapshot.data?.docs ?? [];
          final categoryDocs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final kat = data['kategoriKegiatan'];
            return _sameCategory(kat, widget.filterKategorial);
          }).toList();

          final now = DateTime.now();
          final upcoming = categoryDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final date = _dateFromData(data);
            return date == null || !date.isBefore(now);
          }).toList();
          final history = categoryDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final date = _dateFromData(data);
            return date != null && date.isBefore(now);
          }).toList().reversed.toList();
          final filteredDocs = _showRiwayat ? history : upcoming;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildPengumumanCard(),
              const SizedBox(height: 4),
              Row(
                children: [
                  ChoiceChip(
                    label: Text("Akan Datang (${upcoming.length})"),
                    selected: !_showRiwayat,
                    onSelected: (_) => setState(() => _showRiwayat = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text("Riwayat (${history.length})"),
                    selected: _showRiwayat,
                    onSelected: (_) => setState(() => _showRiwayat = true),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              if (filteredDocs.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 50),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.event_busy, size: 60, color: Colors.grey),
                        SizedBox(height: 10),
                        Text(
                          "Tidak ada jadwal pada bagian ini", 
                          style: TextStyle(color: Colors.grey, fontSize: 16)
                        ),
                      ],
                    )
                  ),
                )
              else
                ...filteredDocs.map((doc) => _buildJadwalCard(doc)),
            ],
          );
        },
      ),
      
      // 👇 TOMBOL TAMBAH HANYA MUNCUL JIKA canEdit == true 👇
      floatingActionButton: canEdit ? FloatingActionButton(
        onPressed: () => _navigasiTambahEdit(null),
        backgroundColor: Colors.indigo,
        elevation: 4,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ) : null,
    );
  }

  Widget _buildPengumumanCard() {
    final kategori = widget.filterKategorial?.trim();
    final docId = (kategori == null || kategori.isEmpty) ? "utama" : "pengumuman_$kategori";
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('churches').doc(churchId).collection('pengumuman').doc(docId).snapshots(),
      builder: (context, snapshot) {
        String teks = "Tidak ada pengumuman khusus.";
        
        if (snapshot.hasData && snapshot.data!.exists) {
          Map<String, dynamic>? dataMap = snapshot.data!.data() as Map<String, dynamic>?;
          
          if (dataMap != null && dataMap.containsKey('teks')) {
            teks = dataMap['teks']?.toString() ?? "";
          }
        }

        return GestureDetector(
          // 👇 PENGUMUMAN BISA DIEDIT JIKA canEdit == true 👇
          onLongPress: canEdit ? () => _showEditPengumumanDialog(docId, teks) : null,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9C4), 
              borderRadius: BorderRadius.circular(15), 
              border: Border.all(color: Colors.orange.shade300, width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.orange.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))
              ]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.campaign, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text("Pengumuman", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800], fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(teks, style: const TextStyle(fontSize: 14, height: 1.4)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildJadwalCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final pelayan = data['pelayan'] as Map<String, dynamic>? ?? {};
    final String namaKeg = data['namaKegiatan'] ?? "-";
    final labelHari = _labelHari(data);
    
    final List<Map<String, dynamic>> rows = [
      {'label': 'W.L', 'val': pelayan['Worship Leader'], 'icon': Icons.mic_external_on},
      {'label': 'Singer', 'val': pelayan['Singer'], 'icon': Icons.queue_music},
      {'label': 'Musik', 'val': pelayan['Pemain Musik'], 'icon': Icons.piano},
      {'label': 'Tamborin', 'val': pelayan['Pemain Tamborin'] ?? pelayan['Tamborin'], 'icon': Icons.celebration}, 
      {'label': 'Operator LCD', 'val': pelayan['Operator LCD'], 'icon': Icons.desktop_mac},
      {'label': 'Kolektan', 'val': pelayan['Kolektan'], 'icon': Icons.volunteer_activism},
      {'label': 'Doa Syafaat', 'val': pelayan['Doa Syafaat'], 'icon': Icons.front_hand},
      {'label': 'Penerima Tamu', 'val': pelayan['Penerima Tamu'], 'icon': Icons.waving_hand},
    ];

    final visibleRows = rows.where((r) => r['val'] != null && r['val'].toString().trim().isNotEmpty).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      child: InkWell(
        // 👇 JADWAL BISA DIHAPUS/EDIT JIKA canEdit == true 👇
        onLongPress: canEdit ? () => _showEditDeleteDialog(doc.id, namaKeg) : null,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.circular(15), 
            border: Border.all(color: Colors.indigo.shade100, width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.indigo.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
            ]
          ),
          child: ExpansionTile(
            title: Row(
              children: [
                Expanded(child: Text(namaKeg, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.indigo))),
                if (labelHari != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(10)),
                    child: Text(labelHari, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                  ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.access_time_filled, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(_formatTanggal(data), style: TextStyle(color: Colors.grey[800], fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 14, color: Colors.redAccent),
                      const SizedBox(width: 6),
                      Expanded(child: Text((data['tempat'] ?? '-').toString(), overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[800], fontSize: 13, fontWeight: FontWeight.w500))),
                    ],
                  ),
                ],
              ),
            ),
            children: [
              const Divider(height: 1),

              if (data['deskripsi'] != null && data['deskripsi'].toString().trim().isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16), 
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50.withOpacity(0.5), 
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.menu_book, size: 16, color: Colors.orange.shade800),
                          const SizedBox(width: 8),
                          Text("Firman Tuhan / Tema:", style: TextStyle(color: Colors.orange.shade800, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${data['deskripsi']}", 
                        style: const TextStyle(
                          fontSize: 18, 
                          fontWeight: FontWeight.w900, 
                          color: Colors.black87,
                          height: 1.4 
                        )
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1.5),
              ],

              ...List.generate(visibleRows.length, (index) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: index % 2 == 0 ? Colors.white : Colors.indigo.shade50.withOpacity(0.3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(visibleRows[index]['icon'], size: 20, color: Colors.indigo.shade300),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 100, 
                        child: Text(visibleRows[index]['label'], style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w500))
                      ),
                      Expanded(
                        child: Text(
                          visibleRows[index]['val'].toString().replaceAll(", ", "\n"), 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87) 
                        )
                      ),
                    ],
                  ),
                );
              }),
              
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Petugas terisi: ${visibleRows.length}/${rows.length}",
                    style: TextStyle(fontSize: 12, color: visibleRows.length == rows.length ? Colors.green.shade700 : Colors.orange.shade800, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _navigasiSusunan(doc.id, namaKeg),
                        icon: const Icon(Icons.list_alt),
                        label: const Text("Susunan Acara", style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo, 
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: "Bagikan jadwal",
                      onPressed: () => _shareJadwal(data, visibleRows),
                      icon: const Icon(Icons.share, color: Colors.indigo),
                    ),
                    // 👇 TOMBOL EDIT MUNCUL JIKA canEdit == true 👇
                    if (canEdit) ...[
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () => _navigasiTambahEdit(doc.id), 
                        icon: const Icon(Icons.edit, color: Colors.orange),
                        label: const Text("Edit", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Colors.orange, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditPengumumanDialog(String docId, String currentText) {
    if (!canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Anda tidak memiliki izin mengubah pengumuman ini."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final controller = TextEditingController(text: currentText);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Update Pengumuman", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller, 
          maxLines: 4,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            hintText: "Ketik pengumuman di sini..."
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            onPressed: () async {
              if (!canEdit) {
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text("Izin pengurus sudah berubah."),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              String teksBaru = controller.text.trim();
              
              Navigator.pop(context);
              
              try {
                await _db.collection('churches').doc(churchId).collection('pengumuman').doc(docId).set({'teks': teksBaru});
                bool notifOk = true;
                if (teksBaru.isNotEmpty) {
                  notifOk = await _sendPengumumanNotification(teksBaru);
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(teksBaru.isEmpty
                        ? "Pengumuman disimpan."
                        : notifOk ? "Pengumuman disimpan & notifikasi dikirim." : "Pengumuman disimpan, tetapi notifikasi gagal dikirim."),
                    backgroundColor: notifOk ? Colors.green : Colors.orange,
                  ));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal menyimpan pengumuman."), backgroundColor: Colors.red));
                }
              }
            }, 
            child: const Text("Simpan & Kirim Notif")
          ),
        ],
      ),
    );
  }

  void _showEditDeleteDialog(String id, String nama) {
    if (!canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Anda tidak memiliki izin mengelola jadwal ini."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text("Kelola: $nama", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.orange), 
            title: const Text("Edit Jadwal"), 
            onTap: () { Navigator.pop(context); _navigasiTambahEdit(id); }
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red), 
            title: const Text("Hapus Jadwal", style: TextStyle(color: Colors.red)), 
            onTap: () {
               Navigator.pop(context);
               showDialog(
                 context: context,
                 builder: (c) => AlertDialog(
                   title: const Text("Hapus Jadwal?"),
                   content: Text("Jadwal '$nama' akan dihapus permanen."),
                   actions: [
                     TextButton(onPressed: () => Navigator.pop(c), child: const Text("Batal")),
                     ElevatedButton(
                       style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                       onPressed: () async {
                         if (!canEdit) {
                           if (c.mounted) Navigator.pop(c);
                           if (mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(
                               const SnackBar(
                                 content: Text("Izin pengurus sudah berubah."),
                                 backgroundColor: Colors.red,
                               ),
                             );
                           }
                           return;
                         }
                         try {
                           final ref = _db
                               .collection('churches')
                               .doc(churchId)
                               .collection('jadwal')
                               .doc(id);
                           final latest = await ref.get();
                           if (!latest.exists) {
                             throw StateError("Jadwal sudah tidak tersedia");
                           }
                           final latestData = latest.data()!;
                           final latestCategory =
                               latestData['kategoriKegiatan']?.toString();
                           if (!_sameCategory(
                             latestCategory,
                             widget.filterKategorial,
                           ) ||
                               !_canManageCategory(latestCategory)) {
                             if (c.mounted) Navigator.pop(c);
                             if (mounted) {
                               ScaffoldMessenger.of(context).showSnackBar(
                                 const SnackBar(
                                   content: Text(
                                     "Kategori atau izin jadwal sudah berubah.",
                                   ),
                                   backgroundColor: Colors.red,
                                 ),
                               );
                             }
                             return;
                           }
                           await ref.delete();
                           if (c.mounted) Navigator.pop(c);
                           if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Jadwal dihapus.")));
                         } catch (_) {
                           if (c.mounted) Navigator.pop(c);
                           if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal menghapus jadwal."), backgroundColor: Colors.red));
                         }
                       }, 
                       child: const Text("Hapus", style: TextStyle(color: Colors.white))
                     )
                   ]
                 )
               );
            }
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _shareJadwal(Map<String, dynamic> data, List<Map<String, dynamic>> visibleRows) {
    final nama = (data['namaKegiatan'] ?? 'Jadwal Gereja').toString();
    final tempat = (data['tempat'] ?? '-').toString();
    final petugas = visibleRows.map((r) => "${r['label']}: ${r['val']}").join("\n");
    final text = "$nama\n${_formatTanggal(data)}\nTempat: $tempat${petugas.isEmpty ? '' : '\n\nPetugas Pelayanan:\n$petugas'}";
    Share.share(text);
  }

  void _navigasiSusunan(String jadwalId, String namaKegiatan) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => SusunanAcaraPage(
      jadwalId: jadwalId,
      namaKegiatan: namaKegiatan,
      filterKategorial: widget.filterKategorial,
    )));
  }

  void _navigasiTambahEdit(String? jadwalId) {
    if (!canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Anda tidak memiliki izin mengelola jadwal ini."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditJadwalPage(
          jadwalId: jadwalId,
          filterKategorial: widget.filterKategorial,
        ),
      ),
    );
  }
}