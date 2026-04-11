import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class OfflineAudioPage extends StatefulWidget {
  const OfflineAudioPage({super.key});

  @override
  State<OfflineAudioPage> createState() => _OfflineAudioPageState();
}

class _OfflineAudioPageState extends State<OfflineAudioPage> {
  final Map<int, double> _downloadProgress = {};
  final Map<int, bool> _isDownloaded = {};

  final List<String> _bookNames = [
    "Kejadian", "Keluaran", "Imamat", "Bilangan", "Ulangan", "Yosua", "Hakim-hakim", "Rut", "1 Samuel", "2 Samuel",
    "1 Raja-raja", "2 Raja-raja", "1 Tawarikh", "2 Tawarikh", "Ezra", "Nehemia", "Ester", "Ayub", "Mazmur", "Amsal",
    "Pengkhotbah", "Kidung Agung", "Yesaya", "Yeremia", "Ratapan", "Yehezkiel", "Daniel", "Hosea", "Yoël", "Amos",
    "Obaja", "Yunus", "Mikha", "Nahum", "Habakuk", "Zefanya", "Hagai", "Zakharia", "Maleakhi",
    "Matius", "Markus", "Lukas", "Yohanes", "Kisah Para Rasul", "Roma", "1 Korintus", "2 Korintus", "Galatia", "Efesus",
    "Filipi", "Kolose", "1 Tesalonika", "2 Tesalonika", "1 Timotius", "2 Timotius", "Titus", "Filemon", "Ibrani", "Yakobus",
    "1 Petrus", "2 Petrus", "1 Yohanes", "2 Yohanes", "3 Yohanes", "Yudas", "Wahyu"
  ];

  // 👇 INI DATA AUDIO FULL 66 KITAB HASIL REKAPAN DARI SCREENSHOT BOS 👇
  final Map<int, Map<String, String>> _bibleAudioMap = {
    1: {"folder": "kejadian", "file": "01_kej"},
    2: {"folder": "keluaran", "file": "02_kel"},
    3: {"folder": "imamat", "file": "03_ima"},
    4: {"folder": "bilangan", "file": "04_bil"},
    5: {"folder": "ulangan", "file": "05_ula"},
    6: {"folder": "yosua", "file": "06_yos"},
    7: {"folder": "hakim-hakim", "file": "07_hak"},
    8: {"folder": "rut", "file": "08_rut"},
    9: {"folder": "1samuel", "file": "09_1sa"},
    10: {"folder": "2samuel", "file": "10_2sa"},
    11: {"folder": "1raja-raja", "file": "11_1ra"},
    12: {"folder": "2raja-raja", "file": "12_2ra"},
    13: {"folder": "1tawarikh", "file": "13_1ta"},
    14: {"folder": "2tawarikh", "file": "14_2ta"},
    15: {"folder": "ezra", "file": "15_ezr"},
    16: {"folder": "nehemia", "file": "16_neh"},
    17: {"folder": "ester", "file": "17_est"},
    18: {"folder": "ayub", "file": "18_ayu"},
    19: {"folder": "mazmur", "file": "19_mzm"},
    20: {"folder": "amsal", "file": "20_ams"},
    21: {"folder": "pengkhotbah", "file": "21_pen"},
    22: {"folder": "kidungagung", "file": "22_kid"},
    23: {"folder": "yesaya", "file": "23_yes"},
    24: {"folder": "yeremia", "file": "24_yer"},
    25: {"folder": "ratapan", "file": "25_rat"},
    26: {"folder": "yehezkiel", "file": "26_yeh"},
    27: {"folder": "daniel", "file": "27_dan"},
    28: {"folder": "hosea", "file": "28_hos"},
    29: {"folder": "yoel", "file": "29_yoe"},
    30: {"folder": "amos", "file": "30_amo"},
    31: {"folder": "obaja", "file": "31_oba"},
    32: {"folder": "yunus", "file": "32_yun"},
    33: {"folder": "mikha", "file": "33_mik"},
    34: {"folder": "nahum", "file": "34_nah"},
    35: {"folder": "habakuk", "file": "35_hab"},
    36: {"folder": "zefanya", "file": "36_zef"},
    37: {"folder": "hagai", "file": "37_hag"},
    38: {"folder": "zakharia", "file": "38_zak"},
    39: {"folder": "maleakhi", "file": "39_mal"},
    40: {"folder": "matius", "file": "01_mat"},
    41: {"folder": "markus", "file": "02_mar"},
    42: {"folder": "lukas", "file": "03_luk"},
    43: {"folder": "yohanes", "file": "04_yoh"},
    44: {"folder": "kisahpararasul", "file": "05_kis"},
    45: {"folder": "roma", "file": "06_rom"},
    46: {"folder": "1korintus", "file": "07_1ko"},
    47: {"folder": "2korintus", "file": "08_2ko"},
    48: {"folder": "galatia", "file": "09_gal"},
    49: {"folder": "efesus", "file": "10_efe"},
    50: {"folder": "filipi", "file": "11_flp"},
    51: {"folder": "kolose", "file": "12_kol"},
    52: {"folder": "1tesalonika", "file": "13_1te"},
    53: {"folder": "2tesalonika", "file": "14_2te"},
    54: {"folder": "1timotius", "file": "15_1ti"},
    55: {"folder": "2timotius", "file": "16_2ti"},
    56: {"folder": "titus", "file": "17_tit"},
    57: {"folder": "filemon", "file": "18_fil"},
    58: {"folder": "ibrani", "file": "19_ibr"},
    59: {"folder": "yakobus", "file": "20_yak"},
    60: {"folder": "1petrus", "file": "21_1pe"},
    61: {"folder": "2petrus", "file": "22_2pe"},
    62: {"folder": "1yohanes", "file": "23_1yo"},
    63: {"folder": "2yohanes", "file": "24_2yo"},
    64: {"folder": "3yohanes", "file": "25_3yo"},
    65: {"folder": "yudas", "file": "26_yud"},
    66: {"folder": "wahyu", "file": "27_wah"},
  };

  final Map<int, int> _chaptersPerBook = {
    1: 50,  2: 40,  3: 27,  4: 36,  5: 34,  6: 24,  7: 21,  8: 4,   9: 31,  10: 24, 
    11: 22, 12: 25, 13: 29, 14: 36, 15: 10, 16: 13, 17: 10, 18: 42, 19: 150, 20: 31, 
    21: 12, 22: 8,  23: 66, 24: 52, 25: 5,  26: 48, 27: 12, 28: 14, 29: 3,   30: 9,  
    31: 1,  32: 4,  33: 7,  34: 3,  35: 3,  36: 3,  37: 2,  38: 14, 39: 4,
    40: 28, 41: 16, 42: 24, 43: 21, 44: 28, 45: 16, 46: 16, 47: 13, 48: 6,   49: 6,
    50: 4,  51: 4,  52: 5,  53: 3,  54: 6,  55: 4,  56: 3,  57: 1,  58: 13,  59: 5,
    60: 5,  61: 3,  62: 5,  63: 1,  64: 1,  65: 1,  66: 22
  };

  @override
  void initState() {
    super.initState();
    _checkDownloadedFiles();
  }

  Future<void> _checkDownloadedFiles() async {
    // (Tahap 3: Logika Cek file lokal akan kita masukkan sini nanti)
    setState(() {}); 
  }

  Future<void> _downloadBook(int index) async {
    int bookNum = index + 1; 

    if (!_bibleAudioMap.containsKey(bookNum)) {
      _showSnackBar("Maaf, format audio kitab ini belum didaftarkan.");
      return;
    }

    String folder = _bibleAudioMap[bookNum]!["folder"]!;
    String prefix = _bibleAudioMap[bookNum]!["file"]!;
    
    // Intip Pasal 1 saja untuk mengecek keberadaan file di GitHub
    String testChapter = (folder == "mazmur") ? "001" : "01";
    String testUrl = "https://raw.githubusercontent.com/pulicarpus/gereja_mobile/master/audio/$folder/${prefix}${testChapter}.mp3";

    // Nyalakan animasi loading (muter-muter)
    setState(() { _downloadProgress[bookNum] = 0.01; });

    try {
      // KIRIM RADAR KE GITHUB 
      final response = await http.head(Uri.parse(testUrl));

      if (response.statusCode == 200) {
        // File ada di GitHub! Mulai proses download simulasi
        int totalChapters = _chaptersPerBook[bookNum] ?? 1;
        
        for (int i = 1; i <= totalChapters; i++) {
          // (Simulasi download Tahap 1 & 2)
          await Future.delayed(const Duration(milliseconds: 200)); 
          setState(() { _downloadProgress[bookNum] = i / totalChapters; });
        }

        // Selesai Download
        setState(() {
          _downloadProgress.remove(bookNum);
          _isDownloaded[bookNum] = true;
        });
        _showSnackBar("${_bookNames[index]} berhasil diunduh!");

      } else {
        // FILE TIDAK DITEMUKAN (404)
        setState(() { _downloadProgress.remove(bookNum); });
        _showSnackBar("Audio ${_bookNames[index]} belum diunggah. Akan segera hadir!");
      }

    } catch (e) {
      // ERROR INTERNET
      setState(() { _downloadProgress.remove(bookNum); });
      _showSnackBar("Gagal mengecek server. Periksa koneksi internet.");
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _deleteBook(int index) async {
    int bookNum = index + 1;
    setState(() { _isDownloaded[bookNum] = false; });
    _showSnackBar("Audio ${_bookNames[index]} dihapus.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Audio Alkitab Offline"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        itemCount: _bookNames.length,
        itemBuilder: (context, index) {
          int bookNum = index + 1;
          bool isAvailableOnServer = _bibleAudioMap.containsKey(bookNum); 
          bool isDownloaded = _isDownloaded[bookNum] ?? false;
          double? progress = _downloadProgress[bookNum];

          return ListTile(
            title: Text(_bookNames[index], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              !isAvailableOnServer 
                  ? "Belum didaftarkan" 
                  : isDownloaded 
                      ? "Tersedia Offline" 
                      : "Belum diunduh",
              style: TextStyle(
                color: !isAvailableOnServer ? Colors.redAccent : Colors.grey[600],
                fontStyle: !isAvailableOnServer ? FontStyle.italic : FontStyle.normal,
              ),
            ),
            trailing: !isAvailableOnServer
                ? const Icon(Icons.access_time, color: Colors.grey) 
                : progress != null
                    ? CircularProgressIndicator(value: progress, color: Colors.indigo) 
                    : isDownloaded
                        ? const Icon(Icons.check_circle, color: Colors.green) 
                        : const Icon(Icons.download, color: Colors.indigo), 
            onTap: () {
              if (!isAvailableOnServer) {
                _showSnackBar("Audio kitab ini belum siap. Akan segera hadir!");
                return; 
              }

              if (!isDownloaded && progress == null) {
                _downloadBook(index);
              } else if (isDownloaded) {
                _showSnackBar("Sudah diunduh. Tahan lama untuk menghapus.");
              }
            },
            onLongPress: () {
              if (isAvailableOnServer && isDownloaded) {
                _deleteBook(index);
              }
            },
          );
        },
      ),
    );
  }
}