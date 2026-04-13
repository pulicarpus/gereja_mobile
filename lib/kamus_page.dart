import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

// 👇 IMPORT BRANKAS RAHASIA KITA 👇
import 'secrets.dart';

class KamusPage extends StatefulWidget {
  final String? kataBawaan; // 👇 TIKET MASUK KATA DARI ALKITAB

  const KamusPage({super.key, this.kataBawaan});

  @override
  State<KamusPage> createState() => _KamusPageState();
}

class _KamusPageState extends State<KamusPage> {
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  String _hasilArti = "";
  bool _isSearching = false;

  final _model = GenerativeModel(
    model: 'gemini-2.5-flash',
    apiKey: geminiApiKey, 
  );

  // 👇 TAMBAHKAN BLOK INI (AUTO-JALAN SAAT HALAMAN DIBUKA) 👇
  @override
  void initState() {
    super.initState();
    // Kalau ada kata yang dikirim dari Alkitab, langsung tembak!
    if (widget.kataBawaan != null && widget.kataBawaan!.isNotEmpty) {
      _searchController.text = widget.kataBawaan!;
      
      // Kasih jeda sedikit biar UI-nya selesai dimuat dulu
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _cariKamus(widget.kataBawaan!);
      });
    }
  }
  // 👆 SAMPAI SINI 👆

  // ... (Sisa kodenya _cariKamus dll biarkan sama persis seperti sebelumnya)

  Future<void> _cariKamus(String kata) async {
    String kataQuery = kata.trim().toLowerCase();
    if (kataQuery.isEmpty) return;

    // Sembunyikan keyboard setelah menekan enter/search
    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = true;
      _hasilArti = "Mencari di dalam database GKII Global...";
    });

    try {
      // 1. CEK DATABASE PUSAT 'kamus_global' DI FIREBASE
      DocumentSnapshot doc = await _db.collection('kamus_global').doc(kataQuery).get();

      if (doc.exists) {
        // JIKA ADA: Langsung tampilkan hasil dari jemaat/gereja lain yang pernah cari (Hemat Kuota AI & Cepat!)
        setState(() {
          _hasilArti = doc['arti'];
          _isSearching = false;
        });
      } else {
        // JIKA TIDAK ADA: Panggil Gemini dengan PROMPT SATPAM
        setState(() => _hasilArti = "Kata baru! Meminta bantuan AI Gemini...");
        
// 👇 PROMPT ENSIKLOPEDIA + TAFSIRAN INJILI 👇
        final prompt = """
        Saya sedang membuat Kamus Ensiklopedia dan Tafsiran Alkitab untuk aplikasi gereja GKII (beraliran Kristen Injili). 
        Tolong jelaskan kata '$kata' secara MENDALAM, teologis, dan komprehensif. 
        SYARAT SANGAT PENTING: Jika kata tersebut sama sekali BUKAN istilah Alkitab, BUKAN nama tokoh/tempat di Alkitab, kata acak, atau tidak pantas, WAJIB membalas HANYA dengan teks: "KATA_TIDAK_VALID".
        Jika valid, berikan penjelasan TANPA format markdown (jangan pakai tanda bintang ** atau pagar #, karena aplikasi tidak bisa membacanya). Susun dengan struktur yang rapi persis seperti ini:

        ETIMOLOGI & BAHASA ASLI:
        (Sebutkan asal kata ini dalam bahasa Ibrani/Yunani/Aram beserta arti harfiahnya)

        DEFINISI SINGKAT:
        (Jelaskan siapa/apa itu secara ringkas)

        LATAR BELAKANG & SEJARAH:
        (Jelaskan konteks sejarah, budaya, atau asal-usulnya di masa Alkitab)

        TAFSIRAN & MAKNA ROHANI:
        (Berikan tafsiran teologis yang mendalam berdasarkan pandangan Kristen Injili. Jelaskan nubuatan, bayangan akan Kristus (tipologi), atau makna keselamatan di baliknya)

        APLIKASI PRAKTIS UNTUK JEMAAT:
        (Apa pelajaran konkret yang bisa diterapkan oleh jemaat Kristen di masa kini dari kata/tokoh ini?)

        REFERENSI AYAT KUNCI:
        (Sebutkan 2-3 ayat utama lengkap dengan bunyi ayatnya secara ringkas)
        """;
        
        final content = [Content.text(prompt)];
        final response = await _model.generateContent(content);
        
        String jawabanGemini = (response.text ?? "").trim();

        if (jawabanGemini.contains("KATA_TIDAK_VALID")) {
          // JIKA KATA NGAWUR: Tolak dan jangan simpan ke Firebase!
          setState(() {
            _hasilArti = "Maaf, '$kata' tidak ditemukan dalam konteks istilah Alkitab, atau penulisan salah. Silakan coba kata lain.";
            _isSearching = false;
          });
        } else {
          // JIKA KATA VALID: Simpan ke Database Pusat (Sumbangan amal untuk semua gereja)
          await _db.collection('kamus_global').doc(kataQuery).set({
            'kata_asli': kata,
            'arti': jawabanGemini,
            'dicari_pada': FieldValue.serverTimestamp(),
          });

          setState(() {
            _hasilArti = jawabanGemini;
            _isSearching = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _hasilArti = "Gagal memuat pencarian. Pastikan Anda memiliki koneksi internet yang stabil untuk mencari kata baru atau API Key Anda aktif.";
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Kamus Alkitab Pintar", style: TextStyle(fontWeight: FontWeight.bold)), 
        backgroundColor: Colors.indigo[900], 
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 👇 BAGIAN KOTAK PENCARIAN 👇
          Container(
            color: Colors.indigo[900],
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                hintText: "Ketik kata (contoh: Kasih, Manna...)",
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.menu_book, color: Colors.indigo),
                suffixIcon: _isSearching 
                    ? const Padding(
                        padding: EdgeInsets.all(12), 
                        child: CircularProgressIndicator(strokeWidth: 2)
                      )
                    : IconButton(
                        icon: const Icon(Icons.search, color: Colors.indigo, size: 28), 
                        onPressed: () => _cariKamus(_searchController.text)
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30), 
                  borderSide: BorderSide.none
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              ),
              onSubmitted: _cariKamus,
            ),
          ),
          
          // 👇 BAGIAN HASIL PENCARIAN 👇
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _hasilArti.isEmpty
                  // TAMPILAN AWAL SEBELUM MENCARI
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 50),
                          Icon(Icons.travel_explore, size: 80, color: Colors.indigo.withOpacity(0.2)),
                          const SizedBox(height: 20),
                          Text(
                            "Ketik istilah atau nama tokoh Alkitab\nyang ingin Anda pelajari artinya.", 
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 15, height: 1.5)
                          ),
                        ],
                      ),
                    )
                  // TAMPILAN HASIL/LOADING
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white, 
                        borderRadius: BorderRadius.circular(20), 
                        border: Border.all(color: Colors.indigo.shade100),
                        boxShadow: [
                          BoxShadow(color: Colors.indigo.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
                        ]
                      ),
                      child: Text(
                        _hasilArti, 
                        style: const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87), 
                        textAlign: TextAlign.justify
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}