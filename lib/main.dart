import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';

// Import file-file pendukung
import 'user_manager.dart';
import 'login_page.dart';
import 'data_jemaat_page.dart';
import 'jadwal_page.dart';
import 'alkitab_page.dart';    
import 'renungan_page.dart';   
import 'lagu_page.dart';       
import 'kelola_gereja_page.dart';
import 'chatroom_page.dart'; 
import 'ayat_data.dart';
import 'keuangan_page.dart'; 
import 'gallery_page.dart';
import 'kategorial_page.dart'; 
import 'doa_page.dart';
import 'pengurus_page.dart';
import 'daftar_pengguna_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  await initializeDateFormatting('id_ID', null);
  
  _initOneSignal();
  
  runApp(const MyApp());
}

void _initOneSignal() {
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  OneSignal.initialize("a9ff250a-56ef-413d-b825-67288008d614"); // Ganti dengan App ID Bos jika perlu
  OneSignal.Notifications.requestPermission(true);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GKII SILOAM',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: FirebaseAuth.instance.currentUser == null 
          ? const LoginPage() 
          : const MainActivity(),
      routes: {
        '/home': (context) => const MainActivity(),
        '/login': (context) => const LoginPage(),
      },
    );
  }
}

class MainActivity extends StatefulWidget {
  const MainActivity({super.key});

  @override
  State<MainActivity> createState() => _MainActivityState();
}

class _MainActivityState extends State<MainActivity> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();
  
  String? _fotoGembalaUrl;
  String _namaGembala = "Gembala Sidang";
  String _alamatGereja = "Memuat alamat...";
  String? _fotoGerejaUrl;
  
  // Media Sosial Gembala
  String _waGembala = "";
  String _fbGembala = "";
  String _igGembala = "";
  String _tiktokGembala = "";
  String _ytGembala = "";
  
  late Map<String, String> _ayatEmas;
  bool _isLoadingUpload = false;

  @override
  void initState() {
    super.initState();
    _ayatEmas = AyatData.getAyatAcak();
    _initSession();
  }

  void _initSession() async {
    final userManager = UserManager();
    await userManager.loadFromPrefs();
    
    _setupOneSignal();
    _loadDataGereja();
    
    if (mounted) setState(() {}); 
  }

  void _setupOneSignal() {
    final user = _auth.currentUser;
    if (user != null) {
      OneSignal.login(user.uid);
    }
  }

  void _loadDataGereja() {
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) return;

    _db.collection("churches").doc(churchId).snapshots().listen((snapshot) {
      if (snapshot.exists && mounted) {
        setState(() {
          var data = snapshot.data();
          _namaGembala = data?['namaGembala'] ?? "Gembala Sidang";
          _fotoGembalaUrl = data?['fotoGembalaUrl'];
          _alamatGereja = data?['alamat'] ?? "Alamat tidak tersedia";
          _fotoGerejaUrl = data?['fotoGerejaUrl'];
          
          _waGembala = data?['waGembala'] ?? "";
          _fbGembala = data?['fbGembala'] ?? "";
          _igGembala = data?['igGembala'] ?? "";
          _tiktokGembala = data?['tiktokGembala'] ?? "";
          _ytGembala = data?['ytGembala'] ?? "";
        });
      }
    });
  }

  // 👇 FUNGSI GANTI FOTO GEREJA (ADMIN/SUPERADMIN) 👇
  Future<void> _ubahFotoGereja() async {
    final user = UserManager();
    if (!user.isAdmin() && !user.isSuperAdmin()) return;

    final pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile == null) return;

    setState(() => _isLoadingUpload = true);
    try {
      String churchId = user.activeChurchId!;
      File imageFile = File(pickedFile.path);
      String fileName = "header_${DateTime.now().millisecondsSinceEpoch}.jpg";
      Reference ref = _storage.ref().child("gereja/$churchId/$fileName");
      
      await ref.putFile(imageFile);
      String url = await ref.getDownloadURL();

      await _db.collection("churches").doc(churchId).update({
        "fotoGerejaUrl": url
      });
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Foto Gereja berhasil diperbarui.")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal upload foto: $e")));
    } finally {
      if (mounted) setState(() => _isLoadingUpload = false);
    }
  }

  // 👇 FUNGSI EDIT PROFIL GEMBALA 👇
  void _tampilkanDialogEditGembala() {
    final user = UserManager();
    if (!user.isAdmin() && !user.isSuperAdmin()) return;

    File? imageFile;
    final txtNama = TextEditingController(text: _namaGembala);
    final txtWa = TextEditingController(text: _waGembala);
    final txtFb = TextEditingController(text: _fbGembala);
    final txtIg = TextEditingController(text: _igGembala);
    final txtTiktok = TextEditingController(text: _tiktokGembala);
    final txtYt = TextEditingController(text: _ytGembala);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Edit Profil Gembala", style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                    if (pickedFile != null) setStateDialog(() => imageFile = File(pickedFile.path));
                  },
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.indigo.shade50,
                    backgroundImage: imageFile != null 
                        ? FileImage(imageFile!) 
                        : (_fotoGembalaUrl != null ? CachedNetworkImageProvider(_fotoGembalaUrl!) : null) as ImageProvider?,
                    child: (imageFile == null && _fotoGembalaUrl == null) ? const Icon(Icons.camera_alt, size: 40, color: Colors.indigo) : null,
                  ),
                ),
                const SizedBox(height: 8),
                const Text("Ketuk foto untuk mengubah", style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                TextField(controller: txtNama, decoration: const InputDecoration(labelText: "Nama Gembala", border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: txtWa, decoration: const InputDecoration(labelText: "WhatsApp (Cth: 0812...)", prefixIcon: Icon(Icons.phone), border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: txtFb, decoration: const InputDecoration(labelText: "Link Facebook", prefixIcon: Icon(Icons.facebook), border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: txtIg, decoration: const InputDecoration(labelText: "Link Instagram", prefixIcon: Icon(Icons.camera_alt_outlined), border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: txtTiktok, decoration: const InputDecoration(labelText: "Link TikTok", prefixIcon: Icon(Icons.music_video), border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: txtYt, decoration: const InputDecoration(labelText: "Link YouTube", prefixIcon: Icon(Icons.play_circle_fill), border: OutlineInputBorder())),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: () async {
                setState(() => _isLoadingUpload = true);
                Navigator.pop(context);

                String? finalFotoUrl = _fotoGembalaUrl;
                String churchId = user.activeChurchId!;

                try {
                  if (imageFile != null) {
                    String fileName = "gembala_${DateTime.now().millisecondsSinceEpoch}.jpg";
                    Reference ref = _storage.ref().child("gereja/$churchId/$fileName");
                    await ref.putFile(imageFile!);
                    finalFotoUrl = await ref.getDownloadURL();
                  }

                  await _db.collection("churches").doc(churchId).update({
                    "namaGembala": txtNama.text.trim(),
                    "waGembala": txtWa.text.trim(),
                    "fbGembala": txtFb.text.trim(),
                    "igGembala": txtIg.text.trim(),
                    "tiktokGembala": txtTiktok.text.trim(),
                    "ytGembala": txtYt.text.trim(),
                    if (finalFotoUrl != null) "fotoGembalaUrl": finalFotoUrl,
                  });
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profil Gembala diperbarui.")));
                } catch (e) {
                   if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal menyimpan: $e")));
                } finally {
                  if (mounted) setState(() => _isLoadingUpload = false);
                }
              },
              child: const Text("Simpan"),
            ),
          ],
        ),
      ),
    );
  }

  void _bukaLink(String urlString) async {
    if (urlString.isEmpty) return;
    
    // Perbaiki link WA jika dimulai dengan 0
    if (urlString.startsWith("0")) {
       urlString = "https://wa.me/62${urlString.substring(1)}";
    }

    Uri uri = Uri.parse(urlString);
    if (!urlString.startsWith("http")) {
       uri = Uri.parse("https://$urlString");
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tidak dapat membuka tautan.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = UserManager();
    bool isAdmin = user.isAdmin();
    bool isSuperAdmin = user.isSuperAdmin();
    bool isMemantau = isSuperAdmin && (user.activeChurchId != user.originalChurchId);

    return Scaffold(
      appBar: AppBar(
        title: Text(user.activeChurchName ?? "GKII SILOAM", style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo[900],
        // 👇 TAMBAHKAN BLOK ACTIONS INI 👇
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.indigo),
            tooltip: "Tentang Aplikasi",
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (context) => const TentangAplikasiPage()
              ));
            },
          ),
          const SizedBox(width: 8), // Memberi sedikit jarak dari pinggir layar
        ],
        // 👆 ========================== 👆
      ),
      drawer: _buildDrawer(user, isAdmin, isSuperAdmin),
// ...
      body: _isLoadingUpload 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  if (isMemantau)
                    Container(
                      color: Colors.orange.shade100,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(Icons.visibility, color: Colors.deepOrange),
                          const SizedBox(width: 8),
                          Expanded(child: Text("Mode Pantau: ${user.activeChurchName}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 13))),
                          ElevatedButton(
                            onPressed: () async {
                              await user.exitChurchContext();
                              setState(() { _initSession(); });
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                            child: const Text("KEMBALI"),
                          )
                        ],
                      ),
                    ),

                  // 👇 FOTO HEADER GEREJA 👇
                  GestureDetector(
                    onTap: (isAdmin || isSuperAdmin) ? _ubahFotoGereja : null,
                    child: Stack(
                      children: [
                        Container(
                          width: double.infinity, height: 220,
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            image: _fotoGerejaUrl != null ? DecorationImage(image: CachedNetworkImageProvider(_fotoGerejaUrl!), fit: BoxFit.cover) : null,
                          ),
                          child: _fotoGerejaUrl == null ? Icon(Icons.church, size: 80, color: Colors.indigo.withOpacity(0.3)) : null,
                        ),
                        if (isAdmin || isSuperAdmin)
                          Positioned(
                            bottom: 10, right: 10,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                              child: const Row(
                                children: [
                                  Icon(Icons.edit, color: Colors.white, size: 16),
                                  SizedBox(width: 4),
                                  Text("Ubah Foto", style: TextStyle(color: Colors.white, fontSize: 12)),
                                ],
                              ),
                            ),
                          )
                      ],
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.activeChurchName ?? "GKII SILOAM", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 18, color: Colors.redAccent),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_alamatGereja, style: const TextStyle(color: Colors.black87, fontSize: 14))),
                          ],
                        ),
                        const SizedBox(height: 25),
                        
                        GestureDetector(
                          onTap: () {
                            setState(() { _ayatEmas = AyatData.getAyatAcak(); });
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50, 
                              borderRadius: BorderRadius.circular(20), 
                              border: Border.all(color: Colors.indigo.shade100)
                            ),
                            child: Column(
                              children: [
                                const Icon(Icons.format_quote, color: Colors.indigo, size: 30),
                                Text(
                                  "\"${_ayatEmas['isi']}\"", 
                                  textAlign: TextAlign.center, 
                                  style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 16, height: 1.5, color: Colors.black87)
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  "- ${_ayatEmas['ref']}", 
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 35),
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Gembala Sidang", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            if (isAdmin || isSuperAdmin)
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.indigo),
                                onPressed: _tampilkanDialogEditGembala,
                                tooltip: "Edit Profil Gembala",
                              )
                          ],
                        ),
                        const SizedBox(height: 10),
                        
                        // 👇 KARTU GEMBALA (DENGAN MEDSOS) 👇
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 35, backgroundColor: Colors.indigo.shade100,
                                    backgroundImage: _fotoGembalaUrl != null ? CachedNetworkImageProvider(_fotoGembalaUrl!) : null,
                                    child: _fotoGembalaUrl == null ? const Icon(Icons.person, size: 35, color: Colors.indigo) : null,
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_namaGembala, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        const Text("Pelayan Tuhan", style: TextStyle(color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (_waGembala.isNotEmpty || _fbGembala.isNotEmpty || _igGembala.isNotEmpty || _tiktokGembala.isNotEmpty || _ytGembala.isNotEmpty) ...[
                                const Divider(height: 30),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    if (_waGembala.isNotEmpty) _buildSosmedIcon(Icons.phone, Colors.green, () => _bukaLink(_waGembala)),
                                    if (_fbGembala.isNotEmpty) _buildSosmedIcon(Icons.facebook, Colors.blue, () => _bukaLink(_fbGembala)),
                                    if (_igGembala.isNotEmpty) _buildSosmedIcon(Icons.camera_alt, Colors.purple, () => _bukaLink(_igGembala)),
                                    if (_tiktokGembala.isNotEmpty) _buildSosmedIcon(Icons.music_note, Colors.black, () => _bukaLink(_tiktokGembala)),
                                    if (_ytGembala.isNotEmpty) _buildSosmedIcon(Icons.play_circle_fill, Colors.red, () => _bukaLink(_ytGembala)),
                                  ],
                                )
                              ]
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 35),
                        
                        // 👇 WIDGET JEMAAT BERULANG TAHUN 👇
                        const Text("Ulang Tahun Bulan Ini", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 15),
                        _buildWidgetUlangTahun(user.activeChurchId),
                        
                        const SizedBox(height: 50),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSosmedIcon(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  // 👇 FUNGSI UNTUK MENGAMBIL DATA ULANG TAHUN 👇
  Widget _buildWidgetUlangTahun(String? churchId) {
    if (churchId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection("churches").doc(churchId).collection("jemaat").snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Text("Belum ada data jemaat.", style: TextStyle(color: Colors.grey));
        }

        List<Map<String, dynamic>> ultahList = [];
        String bulanSekarang = DateFormat('MM').format(DateTime.now());
        String tanggalSekarang = DateFormat('dd').format(DateTime.now());

        for (var doc in snapshot.data!.docs) {
          var data = doc.data() as Map<String, dynamic>;
          String tglLahir = data['tanggalLahir'] ?? ""; // Format: dd-MM-yyyy

          if (tglLahir.length >= 10) {
            String hariLahir = tglLahir.substring(0, 2);
            String bulanLahir = tglLahir.substring(3, 5);

            if (bulanLahir == bulanSekarang) {
              data['isHariIni'] = (hariLahir == tanggalSekarang);
              ultahList.add(data);
            }
          }
        }

        if (ultahList.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
            child: const Row(
              children: [
                Icon(Icons.cake, color: Colors.grey),
                SizedBox(width: 10),
                Text("Tidak ada jemaat yang berulang tahun bulan ini.", style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ultahList.length,
          itemBuilder: (context, index) {
            var jemaat = ultahList[index];
            bool isHariIni = jemaat['isHariIni'] ?? false;

            return Card(
              elevation: 0,
              color: isHariIni ? Colors.orange.shade50 : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: isHariIni ? Colors.orange.shade300 : Colors.grey.shade200)
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isHariIni ? Colors.orange : Colors.indigo.shade100,
                  backgroundImage: jemaat['fotoProfil'] != null ? CachedNetworkImageProvider(jemaat['fotoProfil']) : null,
                  child: jemaat['fotoProfil'] == null ? Icon(Icons.person, color: isHariIni ? Colors.white : Colors.indigo) : null,
                ),
                title: Text(jemaat['namaLengkap'] ?? "Nama", style: TextStyle(fontWeight: FontWeight.bold, color: isHariIni ? Colors.orange.shade900 : Colors.black87)),
                subtitle: Text("Lahir: ${jemaat['tanggalLahir']}", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                trailing: isHariIni 
                    ? const Icon(Icons.cake, color: Colors.orange) 
                    : const Icon(Icons.calendar_month, color: Colors.grey, size: 16),
              ),
            );
          },
        );
      },
    );
  }

  // WIDGET DRAWER (MENU SAMPING)
  Widget _buildDrawer(UserManager user, bool isAdmin, bool isSuperAdmin) {
     return Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A237E), Colors.indigo], 
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: CircleAvatar(
                        radius: 35,
                        backgroundColor: Colors.indigo[100],
                        backgroundImage: user.userFotoUrl != null 
                            ? CachedNetworkImageProvider(user.userFotoUrl!) 
                            : null,
                        child: user.userFotoUrl == null 
                            ? const Icon(Icons.person, size: 40, color: Colors.indigo) 
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user.userNama ?? "Jemaat",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white, 
                        fontSize: 16, 
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      user.activeChurchName ?? "GKII SILOAM",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7), 
                        fontSize: 11
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: GridView.count(
                padding: const EdgeInsets.all(15),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.1,
                children: [
                  _buildDrawerItem(Icons.people, isAdmin ? "Kelola Anggota" : "Data Jemaat", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const DataJemaatPage()));
                  }),
                  _buildDrawerItem(Icons.calendar_month, "Jadwal", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const JadwalPage()));
                  }),
                  _buildDrawerItem(Icons.account_balance_wallet, "Keuangan", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const KeuanganPage()));
                  }),
                  _buildDrawerItem(Icons.volunteer_activism, "Pokok Doa", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const DoaPage()));
                  }),
                  _buildDrawerItem(Icons.chat, "Ruang Chat", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const ChatroomPage()));
                  }),
                  _buildDrawerItem(Icons.book, "Renungan", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const RenunganPage()));
                  }),
                  _buildDrawerItem(Icons.music_note, "Lagu", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const LaguPage()));
                  }),
                  _buildDrawerItem(Icons.photo_library, "Gallery", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const GalleryPage()));
                  }),
                  _buildDrawerItem(Icons.category, "Kategorial", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const KategorialPage()));
                  }),
                  _buildDrawerItem(Icons.menu_book_outlined, "Alkitab", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AlkitabPage()));
                  }),
                  _buildDrawerItem(Icons.supervisor_account, "Pengurus", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const PengurusPage()));
                  }),
                ],
              ),
            ),
            const Divider(),
            
            if (isAdmin || isSuperAdmin) ...[
              ListTile(
                leading: const Icon(Icons.manage_accounts, color: Colors.blue),
                title: const Text("Manajemen Pengguna", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("Atur Role & Kategorial Akun", style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const DaftarPenggunaPage()));
                },
              ),
              const Divider(height: 1),
            ],

            if (isSuperAdmin) ...[
              ListTile(
                leading: const Icon(Icons.admin_panel_settings, color: Colors.orange),
                title: const Text("Kelola Gereja", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("Hak Akses Superadmin", style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const KelolaGerejaPage()))
                  .then((_) => setState(() { _initSession(); }));
                },
              ),
              const Divider(height: 1),
            ],
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Keluar Akun", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () async {
                await _auth.signOut();
                OneSignal.logout();
                if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      );
  }

  Widget _buildDrawerItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: () { Navigator.pop(context); onTap(); },
      borderRadius: BorderRadius.circular(15),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.indigo.shade100),
          boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))]
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.indigo[800], size: 32),
            const SizedBox(height: 12),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
          ],
        ),
      ),
    );
  }
}