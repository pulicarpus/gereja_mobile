import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Untuk fitur Copy to Clipboard

class TentangAplikasiPage extends StatelessWidget {
  const TentangAplikasiPage({super.key});

  // Fungsi untuk menyalin nomor rekening ke clipboard HP
  void _salinRekening(BuildContext context, String noRek) {
    Clipboard.setData(ClipboardData(text: noRek)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Nomor rekening berhasil disalin!"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Background abu-abu bersih
      appBar: AppBar(
        title: const Text("Tentang Aplikasi", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 👇 LOGO DAN VERSI APLIKASI 👇
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.indigo.withOpacity(0.1), blurRadius: 20, spreadRadius: 5)
                ],
              ),
              child: Icon(Icons.church, size: 80, color: Colors.indigo.shade800),
            ),
            const SizedBox(height: 20),
            const Text("GKII SILOAM", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo, letterSpacing: 1.5)),
            const SizedBox(height: 5),
            Text("Versi 2.0.0 (Flutter Edition)", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
            
            const SizedBox(height: 40),

            // 👇 KARTU DESKRIPSI APLIKASI 👇
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.indigo.shade400),
                      const SizedBox(width: 10),
                      const Text("Deskripsi", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                    ],
                  ),
                  const Divider(height: 25),
                  const Text(
                    "Aplikasi ini dirancang secara khusus untuk memudahkan pelayanan jemaat, manajemen kategorial yang terstruktur, dan mewujudkan transparansi keuangan gereja yang lebih baik.",
                    style: TextStyle(fontSize: 14, height: 1.6, color: Colors.black54),
                    textAlign: TextAlign.justify,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 👇 KARTU INFO DEVELOPER 👇
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.code, color: Colors.orange.shade400),
                      const SizedBox(width: 10),
                      const Text("Pengembang", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                    ],
                  ),
                  const Divider(height: 25),
                  const Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.orange,
                        child: Icon(Icons.person, color: Colors.white),
                      ),
                      SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Pulicarpus", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                            Text("Lead Developer / Creator", style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      )
                    ],
                  )
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 👇 KARTU DONASI / SUPPORT DEVELOPER 👇
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.indigo.shade800, Colors.indigo.shade500],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.volunteer_activism, color: Colors.white),
                      SizedBox(width: 10),
                      Text("Dukung Pengembangan", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.account_balance, color: Colors.orange), // Bisa diganti logo BNI kalau ada asetnya
                        ),
                        const SizedBox(width: 15),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Bank BNI", style: TextStyle(color: Colors.white70, fontSize: 13)),
                              Text("1911031551", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2)),
                              Text("a.n Pulicarpus", style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _salinRekening(context, "1911031551"),
                          icon: const Icon(Icons.copy, color: Colors.white),
                          tooltip: "Salin Rekening",
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Center(
                    child: Text(
                      "Terima kasih atas doa dan dukungan Anda.",
                      style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic, fontSize: 12),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}