import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

class RenunganPage extends StatefulWidget {
  const RenunganPage({super.key});

  @override
  State<RenunganPage> createState() => _RenunganPageState();
}

class _RenunganPageState extends State<RenunganPage> {
  late SharedPreferences _prefs;
  
  String _judul = "Memuat...";
  String _isi = "";
  bool _isLoading = false;

  // Variabel untuk Zoom (Pinch-to-zoom)
  double _fontSize = 18.0; // Default sedikit diperbesar bos biar lega
  double _baseFontSize = 18.0;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    _prefs = await SharedPreferences.getInstance();
    _loadOfflineData();
    _ambilDataRenungan();
  }

  void _loadOfflineData() {
    setState(() {
      _judul = _prefs.getString("judul_hari_ini") ?? "Renungan Harian";
      _isi = _prefs.getString("isi_hari_ini") ?? "Sedang mengambil data terbaru...";
    });
  }

  String _getTanggalIndonesia() {
    DateTime n = DateTime.now();
    List<String> hari = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];
    List<String> bulan = ['', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
    
    int indexHari = n.weekday == 7 ? 0 : n.weekday;
    return "${hari[indexHari]}, ${n.day} ${bulan[n.month]} ${n.year}";
  }

  // --- FUNGSI WEBSCRAPING ---
  Future<void> _ambilDataRenungan() async {
    setState(() => _isLoading = true);

    try {
      final response = await http.get(Uri.parse("https://alkitab.mobi/renungan/rh/"))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        dom.Document doc = html_parser.parse(response.body);

        // 1. Cari teks "Bacaan:"
        String bacaan = "";
        final aTags = doc.querySelectorAll("a");
        for (var a in aTags) {
          if (a.attributes['href']?.contains("/tb/") == true) {
            bacaan = a.text.trim();
            break;
          }
        }

        // 2. Cari Judul Renungan
        String judulFix = "Renungan Harian";
        final bTags = doc.querySelectorAll("b");
        for (var b in bTags) {
          String t = b.text.trim();
          if (t.length > 5 && 
              !t.toLowerCase().contains("renungan harian") && 
              !t.contains("Mobile") && 
              !t.contains("Nas:") && 
              !t.toLowerCase().contains("bacaan")) {
            judulFix = t;
            break;
          }
        }

        // 3. Cari Isi Paragraf
        List<String> listIsi = [];
        final pTags = doc.querySelectorAll("p");
        List<String> blacklist = ["<<", ">>", "BCA", "Diskusi renungan", "facebook.com", "Ayat Alkitab:"];

        for (var p in pTags) {
          String teksP = p.text.trim();
          bool isDirty = false;
          
          for (var word in blacklist) {
            if (teksP.toLowerCase().contains(word.toLowerCase())) { 
              isDirty = true; 
              break; 
            }
          }

          if (teksP.length > 15 && 
              !isDirty && 
              teksP.toLowerCase() != judulFix.toLowerCase() && 
              !teksP.startsWith("Bacaan:")) {
            listIsi.add(teksP);
          }
        }

        // 4. Gabungkan hasil
        String isiLengkap = "Bacaan: $bacaan\n\n${listIsi.join('\n\n')}";

        // 5. Simpan ke Offline dan Update UI
        await _prefs.setString("judul_hari_ini", judulFix);
        await _prefs.setString("isi_hari_ini", isiLengkap);

        if (mounted) {
          setState(() {
            _judul = judulFix;
            _isi = isiLengkap;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Gagal sinkron, periksa koneksi internet Anda."))
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- FUNGSI SHARE ---
  void _shareRenungan() {
    final tanggal = _getTanggalIndonesia();
    final teksShare = "*$_judul*\n$tanggal\n\n$_isi\n\n_Sumber: renunganharian.net_";
    Share.share(teksShare, subject: "Renungan: $_judul");
  }

  @override
  Widget build(BuildContext context) {
    // ==== PERBAIKAN WARNA LATAR: Warm Paper Style ====
    const Color mainBgColor = Color(0xFFEFE6D6); // Latar beige hangat di luar kartu
    const Color paperColor = Color(0xFFFCFBF4); // Putih kertas sedikit krem di dalam kartu
    const Color headerIndigo = Color(0xFF1A237E); // Indigo tua untuk header
    // =================================================

    return Scaffold(
      backgroundColor: mainBgColor, // Terapkan latar utama
      appBar: AppBar(
        title: const Text("Renungan Harian"),
        backgroundColor: Colors.indigo[900], 
        foregroundColor: Colors.white,
        elevation: 1, // Beri sedikit elevation bos
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareRenungan,
          )
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _ambilDataRenungan,
            color: Colors.indigo,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(), 
              // Pading luar bos
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0), 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  // AREA TANGGAL (Di luar kartu)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text(
                      _getTanggalIndonesia(),
                      style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // ==== WIDGET KARTU PEMBUNGKUS KONTEN ====
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: paperColor, // Latar kertas
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.grey.shade200), // Garis tipis pembatas
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 5) // Bayangan ke bawah
                        )
                      ]
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // JUDUL RENUNGAN (Indigo Tua)
                        Text(
                          _judul,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: headerIndigo),
                        ),
                        const Divider(height: 35, thickness: 1.2),
                        
                        // ISI RENUNGAN (Off-Black dengan Pinch-to-zoom)
                        GestureDetector(
                          onScaleStart: (details) {
                            _baseFontSize = _fontSize;
                          },
                          onScaleUpdate: (details) {
                            setState(() {
                              _fontSize = (_baseFontSize * details.scale).clamp(14.0, 36.0);
                            });
                          },
                          child: Container(
                            color: Colors.transparent, // Penting!
                            width: double.infinity,
                            child: Text(
                              _isi,
                              style: TextStyle(
                                fontSize: _fontSize, 
                                height: 1.65, // Spasi antar baris dinaikkan sedikit bos biar lega
                                color: Colors.black87 // Off-black tidak terlalu tajam
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ======================================
                  
                  const SizedBox(height: 50), // Jarak ekstra bawah
                ],
              ),
            ),
          ),
          
          if (_isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(backgroundColor: paperColor, color: Colors.indigo,),
            ),
        ],
      ),
    );
  }
}