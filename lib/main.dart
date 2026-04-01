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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Inisialisasi OneSignal sebelum aplikasi jalan
  _initOneSignal();
  
  runApp(const MyApp());
}

void _initOneSignal() {
  // Ganti ID di bawah ini dengan App ID dari dashboard OneSignal Bos
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  OneSignal.initialize("MASUKKAN-APP-ID-ONESIGNAL-DISINI");

  // Minta izin notifikasi untuk Android 13+
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
  
  final String _isiAyat = "TUHAN adalah gembalaku, takkan kekurangan aku.";
  final String _refAyat = "Mazmur 23:1";

  @override
  void initState() {
    super.initState();
    _initSession();
    _loadDataGereja();
    _setupOneSignal();
  }

  void _initSession() async {
    final userManager = UserManager();
    await userManager.loadFromPrefs();
    if (mounted) setState(() {}); 
  }

  void _setupOneSignal() {
    final user = _auth.currentUser;
    // Login ke OneSignal menggunakan UID Firebase agar target user spesifik
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

    return Scaffold(
      appBar: AppBar(
        title: Text(user.activeChurchName ?? "GKII SILOAM"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo,
      ),
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.indigo, Colors.blue],
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
                  _buildDrawerItem(Icons.people, "Jemaat", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const DataJemaatPage()));
                  }),
                  _buildDrawerItem(Icons.calendar_month, "Jadwal", () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const JadwalPage()));
                  }),
                  _buildDrawerItem(Icons.account_balance_wallet, "Keuangan", () {}),
                  _buildDrawerItem(Icons.chat, "Chat", () {}),
                  _buildDrawerItem(Icons.book, "Renungan", () {}),
                  _buildDrawerItem(Icons.music_note, "Lagu", () {}),
                  _buildDrawerItem(Icons.photo_library, "Gallery", () {}),
                  _buildDrawerItem(Icons.front_hand, "Doa", () {}),
                  _buildDrawerItem(Icons.menu_book_outlined, "Alkitab", () {}),
                  _buildDrawerItem(Icons.supervisor_account, "Pengurus", () {}),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Keluar Akun", style: TextStyle(color: Colors.red)),
              onTap: () async {
                await _auth.signOut();
                OneSignal.logout(); // Logout dari OneSignal saat user logout aplikasi
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
            Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                image: _fotoGerejaUrl != null 
                  ? DecorationImage(image: NetworkImage(_fotoGerejaUrl!), fit: BoxFit.cover)
                  : null,
              ),
              child: _fotoGerejaUrl == null 
                ? Icon(Icons.church, size: 80, color: Colors.indigo.withOpacity(0.3))
                : null,
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.activeChurchName ?? "GKII SILOAM",
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 18, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_alamatGereja, style: const TextStyle(color: Colors.black54, fontSize: 14)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.indigo.shade100),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.format_quote, color: Colors.indigo, size: 30),
                        Text(
                          "\"$_isiAyat\"",
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 16, height: 1.5),
                        ),
                        const SizedBox(height: 10),
                        Text("- $_refAyat", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 35),
                  const Text("Gembala Sidang", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 35,
                          backgroundColor: Colors.indigo.shade100,
                          backgroundImage: _fotoGembalaUrl != null 
                              ? CachedNetworkImageProvider(_fotoGembalaUrl!) 
                              : null,
                          child: _fotoGembalaUrl == null ? const Icon(Icons.person, size: 35, color: Colors.indigo) : null,
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_namaGembala, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const Text("Pelayan Tuhan", style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
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
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.indigo, size: 28),
            const SizedBox(height: 10),
            Text(
              label, 
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}