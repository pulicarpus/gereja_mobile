import 'package:flutter/material.dart';
// Anggap saja kita sudah pasang firebase & onesignal nanti

void main() => runApp(const GerejaApp());

class GerejaApp extends StatelessWidget {
  const GerejaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const MainActivityFlutter(),
    );
  }
}

class MainActivityFlutter extends StatefulWidget {
  const MainActivityFlutter({super.key});

  @override
  State<MainActivityFlutter> createState() => _MainActivityFlutterState();
}

class _MainActivityFlutterState extends State<MainActivityFlutter> {
  // Ini pengganti logic "loadInfoHanyaGembala" & "tampilkanAyatEmas" di Kotlin
  String namaGereja = "GKII SILOAM"; 
  String ayatHariIni = "TUHAN adalah gembalaku, takkan kekurangan aku.";
  String referensiAyat = "Mazmur 23:1";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(namaGereja),
        actions: [
          const CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(Icons.person, color: Colors.blue),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Card Ayat Emas (Terjemahan dari tampilkanAyatEmas())
            Card(
              child: ListTile(
                leading: const Icon(Icons.auto_stories),
                title: Text(ayatHariIni),
                subtitle: Text(referensiAyat),
              ),
            ),
            const SizedBox(height: 20),
            // Grid Menu (Terjemahan dari setupListeners() di Kotlin)
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              children: [
                _buildMenuItem(Icons.people, "Jemaat"),
                _buildMenuItem(Icons.event, "Jadwal"),
                _buildMenuItem(Icons.account_balance_wallet, "Keuangan"),
                _buildMenuItem(Icons.chat, "Chat"),
                _buildMenuItem(Icons.book, "Renungan"),
                _buildMenuItem(Icons.library_music, "Lagu"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(child: Icon(icon)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
