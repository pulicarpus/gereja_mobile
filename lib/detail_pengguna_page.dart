import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_manager.dart';

class DetailPenggunaPage extends StatefulWidget {
  final String userId;

  const DetailPenggunaPage({super.key, required this.userId});

  @override
  State<DetailPenggunaPage> createState() => _DetailPenggunaPageState();
}

class _DetailPenggunaPageState extends State<DetailPenggunaPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final UserManager _userManager = UserManager();

  Map<String, dynamic>? _targetUserData;
  String _churchName = "(Belum diatur)";
  // 👇 NAMA VARIABEL TETAP KATEGORIAL DI UI, TAPI NANTI DISIMPAN SEBAGAI 'kelompok' 👇
  String _kategorial = "Umum / Belum diatur"; 
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      var doc = await _db.collection("users").doc(widget.userId).get();
      if (doc.exists) {
        _targetUserData = doc.data();
        
        // 👇 MENGAMBIL DATA MENGGUNAKAN KATA KUNCI 'kelompok' (SESUAI APLIKASI LAMA) 👇
        _kategorial = _targetUserData?['kelompok'] ?? "Umum / Belum diatur";
        
        String? targetChurchId = _targetUserData?['churchId'];
        if (targetChurchId != null && targetChurchId.isNotEmpty) {
          var churchDoc = await _db.collection("churches").doc(targetChurchId).get();
          if (churchDoc.exists) {
            _churchName = churchDoc.data()?['nama'] ?? "(Nama tidak ditemukan)";
          } else {
            _churchName = "(ID Gereja tidak valid)";
          }
        } else {
          _churchName = "(Belum diatur)";
        }
      }
    } catch (e) {
      debugPrint("Gagal memuat data: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateUserRole(String newRole) async {
    String? targetChurchId = _targetUserData?['churchId'];
    
    if (newRole == "admin" && (targetChurchId == null || targetChurchId.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pengguna harus diatur gerejanya terlebih dahulu sebelum dijadikan Admin!"), backgroundColor: Colors.red)
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _db.collection("users").doc(widget.userId).update({"role": newRole});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sukses mengubah role menjadi $newRole")));
      await _loadUserData(); 
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal mengubah role: $e")));
      setState(() => _isLoading = false);
    }
  }

  // 👇 FUNGSI UPDATE MENGGUNAKAN KEY 'kelompok' BUKAN 'kategorial' 👇
  Future<void> _assignUserToKategorial(String kategorialPilihan) async {
    setState(() => _isLoading = true);
    try {
      // 🔥 PERBAIKAN KRUSIAL: Menggunakan 'kelompok' agar sama dengan AddEditJemaatPage
      await _db.collection("users").doc(widget.userId).update({"kelompok": kategorialPilihan});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Jemaat dimasukkan ke kelompok $kategorialPilihan.")));
      await _loadUserData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal menetapkan kategorial: $e")));
      setState(() => _isLoading = false);
    }
  }

  void _showChurchSelectionDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const Padding(padding: EdgeInsets.all(16.0), child: Text("Pilih Gereja", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo))),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<QuerySnapshot>(
                future: _db.collection("churches").get(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("Tidak ada data gereja."));

                  return ListView.builder(
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      var doc = snapshot.data!.docs[index];
                      var gerejaData = doc.data() as Map<String, dynamic>;
                      return ListTile(
                        leading: const Icon(Icons.church, color: Colors.indigo),
                        title: Text(gerejaData['nama'] ?? "Gereja Tanpa Nama", style: const TextStyle(fontWeight: FontWeight.bold)),
                        onTap: () {
                          Navigator.pop(context); 
                          _assignUserToChurch(doc.id);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _showKategorialSelectionDialog() {
    // 👇 DAFTAR SUDAH 100% SAMA DENGAN ADD EDIT JEMAAT PAGE 👇
    final List<String> daftarKategorial = [
      "Sekolah Minggu",
      "AMKI",
      "Perkawan",
      "Perkaria",
      "Lainnya"
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const Padding(
              padding: EdgeInsets.all(16.0), 
              child: Text("Pilih Kategorial", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple))
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: daftarKategorial.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    leading: const Icon(Icons.group, color: Colors.purple),
                    title: Text(daftarKategorial[index], style: const TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(context); 
                      _assignUserToKategorial(daftarKategorial[index]);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Future<void> _assignUserToChurch(String selectedChurchId) async {
    setState(() => _isLoading = true);
    try {
      await _db.collection("users").doc(widget.userId).update({"churchId": selectedChurchId});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pengguna berhasil dimasukkan ke gereja.")));
      await _loadUserData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal menetapkan gereja: $e")));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(appBar: AppBar(title: const Text("Detail Pengguna"), backgroundColor: Colors.indigo[900]), body: const Center(child: CircularProgressIndicator(color: Colors.indigo)));
    }
    if (_targetUserData == null) {
      return Scaffold(appBar: AppBar(title: const Text("Detail Pengguna"), backgroundColor: Colors.indigo[900]), body: const Center(child: Text("Data pengguna tidak ditemukan.")));
    }

    String email = _targetUserData?['email'] ?? "Tidak ada email";
    String role = _targetUserData?['role'] ?? "user";
    String nama = _targetUserData?['nama'] ?? "Jemaat";
    
    bool isSuperAdmin = _userManager.isSuperAdmin();
    bool isAdmin = _userManager.isAdmin();
    String myOriginalChurchId = _userManager.originalChurchId ?? "";
    String targetChurchId = _targetUserData?['churchId'] ?? "";
    bool canManageRoles = isSuperAdmin || (isAdmin && targetChurchId == myOriginalChurchId);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Detail Pengguna", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900], foregroundColor: Colors.white, elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // KARTU PROFIL
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))]),
              child: Column(
                children: [
                  CircleAvatar(radius: 40, backgroundColor: Colors.indigo.shade50, child: Text(nama[0].toUpperCase(), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.indigo))),
                  const SizedBox(height: 16),
                  Text(nama, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 4),
                  Text(email, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  
                  // INFO GEREJA
                  _buildProfileRow(Icons.church, "Gereja Terdaftar", _churchName, Colors.blue),
                  const SizedBox(height: 16),
                  
                  // INFO KATEGORIAL
                  _buildProfileRow(Icons.category, "Kategorial", _kategorial, Colors.purple),
                  const SizedBox(height: 16),
                  
                  // INFO ROLE
                  _buildProfileRow(
                    role == 'admin' || role == 'superadmin' ? Icons.admin_panel_settings : Icons.person, 
                    "Pangkat / Role", 
                    role.toUpperCase(), 
                    role == 'admin' ? Colors.orange : Colors.green
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // AREA TOMBOL AKSI
            if (canManageRoles) ...[
              const Align(alignment: Alignment.centerLeft, child: Text("TINDAKAN", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13))),
              const SizedBox(height: 10),

              _buildActionButton("Atur Kategorial", Icons.category, Colors.purple, _showKategorialSelectionDialog),

              if (role == "user")
                _buildActionButton("Jadikan Admin", Icons.arrow_upward, Colors.orange, () => _updateUserRole("admin")),
              
              if (role == "admin" && !isSuperAdmin) 
                _buildActionButton("Turunkan ke Jemaat Biasa", Icons.arrow_downward, Colors.grey.shade700, () => _updateUserRole("user")),
            ],

            if (isSuperAdmin) ...[
              if (role == "admin") 
                _buildActionButton("Turunkan ke Jemaat Biasa", Icons.arrow_downward, Colors.grey.shade700, () => _updateUserRole("user")),
              _buildActionButton("Atur / Pindah Gereja", Icons.swap_horiz, Colors.blue, _showChurchSelectionDialog),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildProfileRow(IconData icon, String title, String value, MaterialColor color) {
    return Row(
      children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.shade50, shape: BoxShape.circle), child: Icon(icon, color: color)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: title == "Pangkat / Role" && value == 'ADMIN' ? Colors.orange.shade800 : Colors.black87)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildActionButton(String title, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white, foregroundColor: color,
          elevation: 1, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          side: BorderSide(color: color.withOpacity(0.3))
        ),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}