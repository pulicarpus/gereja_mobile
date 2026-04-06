import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Import file-file pendukung Bos
import 'user_manager.dart';
import 'login_page.dart';
import 'data_jemaat_page.dart';
import 'jadwal_page.dart';
import 'alkitab_page.dart';    
import 'renungan_page.dart';   
import 'lagu_page.dart';       
import 'kelola_gereja_page.dart';
import 'chatroom_page.dart'; 
import 'ayat_data.dart'; // 👈 IMPORT DATA AYAT EMAS SUDAH MASUK BOS

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  _initOneSignal();
  
  runApp(const MyApp());
}

void _initOneSignal() {
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  // App ID OneSignal Bos
  OneSignal.initialize("a9ff250a-56ef-413d-b825-67288008d614");
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
  
  String? _fotoGembalaUrl;
  String _namaGembala = "Gembala Sidang";
  String _alamatGereja = "Memuat alamat...";
  String? _fotoGerejaUrl;
  
  // 👇 SEKARANG AYATNYA DINAMIS (BERUBAH-UBAH) 👇
  late Map<String, String> _ayatEmas;

  @override
  void initState() {
    super.initState();
    // Ambil ayat acak saat masuk ke Dashboard
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
          _namaGembala = snapshot.data()?['namaGembala'] ?? "Gembala Sidang";
          _fotoGembalaUrl = snapshot.data()?['fotoGembalaUrl'];
          _alamatGereja = snapshot.data()?['alamat'] ?? "Alamat tidak tersedia";
          _fotoGerejaUrl = snapshot.data()?['fotoGerejaUrl'];
        });
      }
    });
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
      ),
      drawer: Drawer(
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
                    const Icon(Icons.church, size: 50, color: Colors.white),
                    const SizedBox(height: 10),
                    Text(
                      user.activeChurchName ?? "MENU UTAMA",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
                    // TODO: Halaman Keuangan
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
                    // TODO: Halaman Gallery
                  }),
                  _buildDrawerItem(Icons.front_hand, "Doa", () {
                    // TODO: Halaman Pokok Doa
                  }),
                  _buildDrawerItem(Icons.menu_book_outlined, "Alkitab", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AlkitabPage()));
                  }),
                  _buildDrawerItem(Icons.supervisor_account, "Pengurus", () {
                    // TODO: Halaman Pengurus
                  }),
                ],
              ),
            ),
            const Divider(),
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
              const Divider(),
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
      ),
      body: SingleChildScrollView(
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

            Container(
              width: double.infinity, height: 220,
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                image: _fotoGerejaUrl != null ? DecorationImage(image: NetworkImage(_fotoGerejaUrl!), fit: BoxFit.cover) : null,
              ),
              child: _fotoGerejaUrl == null ? Icon(Icons.church, size: 80, color: Colors.indigo.withOpacity(0.3)) : null,
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
                  
                  // ==== BAGIAN AYAT EMAS (EDISI REFRESH OTOMATIS) ====
                  GestureDetector(
                    onTap: () {
                      // ✨ Bonus: Klik ayatnya buat ganti ayat baru tanpa restart aplikasi
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
                  
                  const Text("Gembala Sidang", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  
                  InkWell(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Detail Gembala segera hadir!")));
                    },
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))],
                      ),
                      child: Row(
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
                          const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ],
        ),
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