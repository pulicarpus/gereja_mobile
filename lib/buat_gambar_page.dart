import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

// 👇 IMPORT BRANKAS RAHASIA BOS 👇
import 'secrets.dart'; 

class BuatGambarPage extends StatefulWidget {
  final String ayatTeks;
  final String referensi;

  const BuatGambarPage({super.key, required this.ayatTeks, required this.referensi});

  @override
  State<BuatGambarPage> createState() => _BuatGambarPageState();
}

class _BuatGambarPageState extends State<BuatGambarPage> {
  final ScreenshotController _screenshotController = ScreenshotController();
  final TextEditingController _searchController = TextEditingController(); // 👈 KONTROLER PENCARIAN
  
  final String _apiKey = pixabayApiKey; 
  
  List<String> _imageUrls = [];
  String? _selectedImage;
  bool _isLoading = true;
  String _currentTheme = "nature"; 

  final List<Map<String, String>> _themes = [
    {"name": "Alam", "query": "nature"},
    {"name": "Senja", "query": "sunset"},
    {"name": "Gunung", "query": "mountain"},
    {"name": "Salib", "query": "cross"},
    {"name": "Bintang", "query": "starry sky"},
  ];

  @override
  void initState() {
    super.initState();
    _fetchImages(_currentTheme);
  }

  Future<void> _fetchImages(String query) async {
    setState(() => _isLoading = true);
    
    // 👇 Encode URL biar pencarian dengan spasi (misal: "langit malam") aman 👇
    String encodedQuery = Uri.encodeComponent(query);
    
    try {
      final url = Uri.parse("https://pixabay.com/api/?key=$_apiKey&q=$encodedQuery&image_type=photo&orientation=vertical&per_page=20");
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List hits = data['hits'];
        setState(() {
          _imageUrls = hits.map<String>((h) => h['largeImageURL'] as String).toList();
          if (_imageUrls.isNotEmpty) {
            _selectedImage = _imageUrls[0]; 
          }
          _currentTheme = query;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tidak dapat menemukan gambar.")));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal memuat gambar. Cek koneksi internet.")));
    }
  }

  void _shareImage() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Memproses gambar... Sedang dibungkus! 🎁")));
    
    try {
      final imageBytes = await _screenshotController.capture(delay: const Duration(milliseconds: 20));
      if (imageBytes != null) {
        final directory = await getTemporaryDirectory();
        final imagePath = await File('${directory.path}/ayat_gkii.jpg').create();
        await imagePath.writeAsBytes(imageBytes);

        await Share.shareXFiles([XFile(imagePath.path)], text: 'Renungan hari ini: ${widget.referensi}');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal membagikan: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        // 👇 PENCARIAN GAMBAR PINDAH KE SINI BOS 👇
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: "Cari latar (misal: bunga, langit)...",
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Colors.indigo, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                // Sembunyikan keyboard & cari gambar
                FocusScope.of(context).unfocus();
                _fetchImages(value.trim());
              }
            },
          ),
        ),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // --- AREA KANVAS GAMBAR ---
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: AspectRatio(
                  aspectRatio: 9 / 16, 
                  child: Screenshot(
                    controller: _screenshotController,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))],
                        image: _selectedImage != null
                            ? DecorationImage(image: NetworkImage(_selectedImage!), fit: BoxFit.cover)
                            : null,
                      ),
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              color: Colors.black.withOpacity(0.4),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(25.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "\"${widget.ayatTeks}\"",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontSize: 22, height: 1.5, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  "- ${widget.referensi} -",
                                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            bottom: 15, right: 20,
                            child: Row(
                              children: [
                                const Icon(Icons.church, color: Colors.white70, size: 14),
                                const SizedBox(width: 5),
                                Text("GKII Mobile", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // --- AREA TOMBOL FILTER & PILIH GAMBAR ---
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(top: 10, bottom: 10),
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: Row(
                    children: _themes.map((theme) {
                      bool isSelected = _currentTheme == theme["query"];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(theme["name"]!, style: TextStyle(color: isSelected ? Colors.white : Colors.indigo)),
                          selected: isSelected,
                          selectedColor: Colors.indigo,
                          backgroundColor: Colors.indigo.shade50,
                          onSelected: (bool selected) {
                            if (selected) {
                              _searchController.clear();
                              _fetchImages(theme["query"]!);
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 10),
                _isLoading 
                  ? const SizedBox(height: 70, child: Center(child: CircularProgressIndicator()))
                  : SizedBox(
                      height: 70,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        itemCount: _imageUrls.length,
                        itemBuilder: (context, index) {
                          String url = _imageUrls[index];
                          bool isSelected = _selectedImage == url;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedImage = url),
                            child: Container(
                              margin: const EdgeInsets.only(right: 10),
                              width: 55,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: isSelected ? Border.all(color: Colors.orange, width: 3) : null,
                                image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
              ],
            ),
          ),
          
          // 👇 TOMBOL SHARE SULTAN PINDAH KE BAWAH SINI 👇
          Container(
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 5, 20, 20), // Memberi ruang aman di bawah layar
            child: ElevatedButton.icon(
              onPressed: _shareImage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.share, size: 24),
              label: const Text("Bagikan ke WA / IG", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
}