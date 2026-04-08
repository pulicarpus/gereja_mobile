import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class KamusAlkitabPage extends StatefulWidget {
  const KamusAlkitabPage({super.key});

  @override
  State<KamusAlkitabPage> createState() => _KamusAlkitabPageState();
}

class _KamusAlkitabPageState extends State<KamusAlkitabPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  
  // URL default: Kamus SABDA
  String _currentUrl = "https://alkitab.sabda.org/dictionary.php";

  @override
  void initState() {
    super.initState();
    
    // Inisialisasi WebView Controller
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() { _isLoading = true; });
          },
          onPageFinished: (String url) {
            setState(() { _isLoading = false; });
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('''
              Page resource error:
              code: ${error.errorCode}
              description: ${error.description}
              errorType: ${error.errorType}
              isForMainFrame: ${error.isForMainFrame}
            ''');
          },
        ),
      )
      ..loadRequest(Uri.parse(_currentUrl));
  }

  // Fungsi untuk mengeksekusi pencarian
  void _cariKata() {
    String kata = _searchController.text.trim();
    if (kata.isNotEmpty) {
      // Kita langsung memanipulasi URL SABDA untuk melakukan pencarian
      String searchUrl = "https://alkitab.sabda.org/dictionary.php?word=$kata";
      _controller.loadRequest(Uri.parse(searchUrl));
      
      // Sembunyikan keyboard setelah pencarian
      FocusScope.of(context).unfocus();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Kamus Alkitab", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _controller.reload();
            },
            tooltip: "Muat Ulang",
          )
        ],
      ),
      body: Column(
        children: [
          // 👇 BAR PENCARIAN CUSTOM 👇
          Container(
            color: Colors.indigo[900],
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: (_) => _cariKata(), // Tekan enter di keyboard langsung cari
                    decoration: InputDecoration(
                      hintText: "Cari arti kata (misal: Kasih, Sabat)...",
                      hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                      prefixIcon: const Icon(Icons.menu_book, color: Colors.indigo),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey, size: 20),
                        onPressed: () {
                          _searchController.clear();
                        },
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 15),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30), // Bentuk pil elegan
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Tombol Cari Bulat
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.search, color: Colors.white),
                    onPressed: _cariKata,
                  ),
                )
              ],
            ),
          ),
          
          // 👇 LOADING INDICATOR 👇
          if (_isLoading) 
            const LinearProgressIndicator(color: Colors.orange, backgroundColor: Colors.indigo),

          // 👇 AREA BROWSER INTERNAL (Menampilkan Web SABDA) 👇
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                // Overlay loading di tengah layar saat pertama kali buka
                if (_isLoading)
                  Container(
                    color: Colors.white.withOpacity(0.8),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.indigo),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}