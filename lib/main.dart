import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Wajib ada
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'user_manager.dart';
import 'login_page.dart'; // Import halaman login Bos

void main() async {
  // 1. Inisialisasi wajib untuk Flutter & Firebase
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
      // Alur: Cek apakah user sudah login atau belum
      home: FirebaseAuth.instance.currentUser == null 
          ? const LoginPage() 
          : const MainActivity(),
      // PENAMBAHAN RUTE DI SINI
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
  
  final String _isiAyat = "TUHAN adalah gembalaku, takkan kekurangan aku.";
  final String _refAyat = "Mazmur 23:1";

  @override
  void initState() {
    super.initState();
    _initSession();
    _loadInfoGembala();
    _setupOneSignal();
  }

  void _initSession() async {
    final userManager = UserManager();
    await userManager.loadFromPrefs();
    if (mounted) setState(() {}); 
  }

  void _setupOneSignal() {
    final user = _auth.currentUser;
    if (user != null) {
      OneSignal.login(user.uid);
    }
  }

  void _loadInfoGembala() {
    String? churchId = UserManager().activeChurchId;
    if (churchId == null) return;

    _db.collection("churches").doc(churchId).snapshots().listen((snapshot) {
      if (snapshot.exists && mounted) {
        setState(() {
          _namaGembala = snapshot.data()?['namaGembala'] ?? "Gembala Sidang";
          _fotoGembalaUrl = snapshot.data()?['fotoGembalaUrl'];
        });
      }
    });
  }

  void _bukaHalaman(String routeName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Menuju $routeName..."), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = UserManager();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final bool shouldPop = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Keluar"),
            content: const Text("Tutup aplikasi?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Tidak")),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Ya")),
            ],
          ),
        );
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(user.activeChurchName ?? "GKII SILOAM"),
          actions: [
            IconButton(
              icon: CircleAvatar(
                backgroundColor: Colors.indigo.shade100,
                backgroundImage: (user.userFotoUrl != null && user.userFotoUrl!.isNotEmpty)
                    ? NetworkImage(user.userFotoUrl!)
                    : null,
                child: (user.userFotoUrl == null || user.userFotoUrl!.isEmpty)
                    ? const Icon(Icons.person, color: Colors.indigo)
                    : null,
              ),
              onPressed: () => _bukaHalaman("ProfilActivity"),
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              if (user.isSuperAdmin() && user.activeChurchId != user.originalChurchId)
                Container(
                  width: double.infinity,
                  color: Colors.orange.shade100,
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility, color: Colors.orange),
                      const SizedBox(width: 10),
                      Expanded(child: Text("Memantau: ${user.activeChurchName}")),
                      TextButton(
                        onPressed: () async {
                          await user.exitChurchContext();
                          setState(() {});
                        },
                        child: const Text("Keluar"),
                      )
                    ],
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Icon(Icons.menu_book, size: 30, color: Colors.grey),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("\"$_isiAyat\"", style: const TextStyle(fontStyle: FontStyle.italic)),
                              Text("- $_refAyat", style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  children: [
                    _buildMenuItem(Icons.people, "Jemaat", "DataJemaat"),
                    _buildMenuItem(Icons.calendar_month, "Jadwal", "Jadwal"),
                    _buildMenuItem(Icons.account_balance_wallet, "Keuangan", "Keuangan"),
                    _buildMenuItem(Icons.chat, "Chat", "Chatroom"),
                    _buildMenuItem(Icons.book, "Renungan", "Renungan"),
                    _buildMenuItem(Icons.music_note, "Lagu", "BukuLagu"),
                    _buildMenuItem(Icons.photo_library, "Gallery", "Gallery"),
                    _buildMenuItem(Icons.front_hand, "Doa", "Doa"),
                    _buildMenuItem(Icons.menu_book_outlined, "Alkitab", "Alkitab"),
                    _buildMenuItem(Icons.supervisor_account, "Pengurus", "Pengurus"),
                    _buildMenuItem(Icons.category, "Kategorial", "Kategorial"),
                    _buildMenuItem(Icons.info, "About", "About"),
                  ],
                ),
              ),

              const Divider(height: 40),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: _fotoGembalaUrl != null 
                        ? CachedNetworkImageProvider(_fotoGembalaUrl!) 
                        : null,
                      child: _fotoGembalaUrl == null 
                        ? const Icon(Icons.person, size: 35, color: Colors.grey) 
                        : null,
                    ),
                    const SizedBox(width: 15),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_namaGembala, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Text("Gembala Sidang", style: TextStyle(color: Colors.grey)),
                      ],
                    )
                  ],
                ),
              ),

              const SizedBox(height: 20),

              if (user.isAdmin() || user.isSuperAdmin())
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _buildAdminButton(
                        user.isSuperAdmin() ? "Kelola Pengguna" : "Kelola Anggota",
                        Icons.manage_accounts,
                        "KelolaPengguna",
                      ),
                      if (user.isSuperAdmin()) ...[
                        const SizedBox(height: 10),
                        _buildAdminButton("Pilih Gereja", Icons.church, "PilihGereja"),
                        const SizedBox(height: 10),
                        _buildAdminButton("Kelola Gereja", Icons.settings_applications, "KelolaGereja"),
                      ]
                    ],
                  ),
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String label, String route) {
    return InkWell(
      onTap: () => _bukaHalaman(route),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: Colors.indigo, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center, maxLines: 1),
        ],
      ),
    );
  }

  Widget _buildAdminButton(String label, IconData icon, String route) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _bukaHalaman(route),
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}