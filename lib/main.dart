import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'user_manager.dart';
import 'login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
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
  String _alamatGereja = "Alamat Gereja belum diatur";
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
    if (user != null) OneSignal.login(user.uid);
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

  void _bukaHalaman(String routeName) {
    Navigator.pop(context); // Tutup drawer dulu
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Menuju $routeName..."), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = UserManager();

    return Scaffold(
      appBar: AppBar(
        title: Text(user.activeChurchName ?? "GKII SILOAM"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
        ],
      ),
      // 1. DRAWER (MENU KIRI KE KANAN)
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Colors.indigo),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.church, size: 50, color: Colors.white),
                    const SizedBox(height: 10),
                    Text(
                      user.activeChurchName ?? "MENU UTAMA",
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            // 2. GRID MENU DUA BARIS BISA SKROL
            Expanded(
              child: GridView.count(
                padding: const EdgeInsets.all(15),
                crossAxisCount: 2, // Dua baris/kolom
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.2,
                children: [
                  _buildDrawerItem(Icons.people, "Jemaat", () {
  Navigator.push(context, MaterialPageRoute(builder: (context) => const DataJemaatPage()));
}),
                  _buildDrawerItem(Icons.calendar_month, "Jadwal", "Jadwal"),
                  _buildDrawerItem(Icons.account_balance_wallet, "Keuangan", "Keuangan"),
                  _buildDrawerItem(Icons.chat, "Chat", "Chatroom"),
                  _buildDrawerItem(Icons.book, "Renungan", "Renungan"),
                  _buildDrawerItem(Icons.music_note, "Lagu", "BukuLagu"),
                  _buildDrawerItem(Icons.photo_library, "Gallery", "Gallery"),
                  _buildDrawerItem(Icons.front_hand, "Doa", "Doa"),
                  _buildDrawerItem(Icons.menu_book_outlined, "Alkitab", "Alkitab"),
                  _buildDrawerItem(Icons.supervisor_account, "Pengurus", "Pengurus"),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Keluar Akun", style: TextStyle(color: Colors.red)),
              onTap: () async {
                await _auth.signOut();
                if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
              },
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // TAMPILAN UTAMA: INFO GEREJA
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                image: _fotoGerejaUrl != null 
                  ? DecorationImage(image: NetworkImage(_fotoGerejaUrl!), fit: BoxFit.cover)
                  : null,
              ),
              child: _fotoGerejaUrl == null 
                ? const Icon(Icons.church, size: 80, color: Colors.white)
                : null,
            ),
            
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.activeChurchName ?? "GKII SILOAM",
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.indigo),
                      const SizedBox(width: 5),
                      Expanded(child: Text(_alamatGereja, style: const TextStyle(color: Colors.grey))),
                    ],
                  ),
                  const Divider(height: 40),
                  
                  // AYAT HARI INI
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.format_quote, color: Colors.indigo),
                        Text(
                          "\"$_isiAyat\"",
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 16),
                        ),
                        Text("- $_refAyat", style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  const Text("Gembala Sidang", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  
                  // INFO GEMBALA
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundImage: _fotoGembalaUrl != null 
                            ? CachedNetworkImageProvider(_fotoGembalaUrl!) 
                            : null,
                        child: _fotoGembalaUrl == null ? const Icon(Icons.person, size: 40) : null,
                      ),
                      const SizedBox(width: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_namaGembala, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const Text("Melayani sejak 2015", style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String label, String route) {
    return InkWell(
      onTap: () => _bukaHalaman(route),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.indigo, size: 30),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}