import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import 'bible_support.dart';

class OfflineAudioPage extends StatefulWidget {
  const OfflineAudioPage({super.key});

  @override
  State<OfflineAudioPage> createState() => _OfflineAudioPageState();
}

class _OfflineAudioPageState extends State<OfflineAudioPage> {
  final Map<int, double> _downloadProgress = {};
  final Map<int, bool> _isDownloaded = {};

  final List<String> _bookNames = [
    "Kejadian",
    "Keluaran",
    "Imamat",
    "Bilangan",
    "Ulangan",
    "Yosua",
    "Hakim-hakim",
    "Rut",
    "1 Samuel",
    "2 Samuel",
    "1 Raja-raja",
    "2 Raja-raja",
    "1 Tawarikh",
    "2 Tawarikh",
    "Ezra",
    "Nehemia",
    "Ester",
    "Ayub",
    "Mazmur",
    "Amsal",
    "Pengkhotbah",
    "Kidung Agung",
    "Yesaya",
    "Yeremia",
    "Ratapan",
    "Yehezkiel",
    "Daniel",
    "Hosea",
    "Yoël",
    "Amos",
    "Obaja",
    "Yunus",
    "Mikha",
    "Nahum",
    "Habakuk",
    "Zefanya",
    "Hagai",
    "Zakharia",
    "Maleakhi",
    "Matius",
    "Markus",
    "Lukas",
    "Yohanes",
    "Kisah Para Rasul",
    "Roma",
    "1 Korintus",
    "2 Korintus",
    "Galatia",
    "Efesus",
    "Filipi",
    "Kolose",
    "1 Tesalonika",
    "2 Tesalonika",
    "1 Timotius",
    "2 Timotius",
    "Titus",
    "Filemon",
    "Ibrani",
    "Yakobus",
    "1 Petrus",
    "2 Petrus",
    "1 Yohanes",
    "2 Yohanes",
    "3 Yohanes",
    "Yudas",
    "Wahyu",
  ];

  final http.Client _client = http.Client();
  final Set<int> _cancelled = {};
  final Set<int> _busy = {};
  final Map<int, int> _availableChapters = {};

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkDownloadedFiles();
  }

  // 👇 PENGECEK FILE ASLI DI MEMORI HP 👇
  Future<bool> _validFile(File file) async {
    if (!await file.exists() || await file.length() < 3) return false;
    final opened = await file.open();
    try {
      return isMp3Header(await opened.read(3));
    } finally {
      await opened.close();
    }
  }

  Future<int> _countChapters(Directory root, int book) async {
    var count = 0;
    for (var chapter = 1; chapter <= bibleChaptersPerBook[book]!; chapter++) {
      final file = File('${root.path}/audio/${bibleAudioPath(book, chapter)}');
      if (await _validFile(file)) count++;
    }
    return count;
  }

  Future<void> _checkDownloadedFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      for (final book in bibleAudioMap.keys) {
        final count = await _countChapters(dir, book);
        if (!mounted) return;
        if (_busy.contains(book)) continue;
        setState(() {
          _availableChapters[book] = count;
          _isDownloaded[book] = count == bibleChaptersPerBook[book];
        });
      }
    } catch (_) {
      _showSnackBar('Status audio offline belum dapat diperiksa.');
    }
  }

  Future<void> _downloadBook(int index) async {
    final book = index + 1;
    if (!mounted || _busy.contains(book)) return;
    _busy.add(book);
    _cancelled.remove(book);
    setState(() => _downloadProgress[book] = 0);
    Directory? root;
    try {
      root = await getApplicationDocumentsDirectory();
      final total = bibleChaptersPerBook[book]!;
      for (var chapter = 1; chapter <= total; chapter++) {
        if (!mounted || _cancelled.contains(book)) return;
        final relative = bibleAudioPath(book, chapter);
        final file = File('${root.path}/audio/$relative');
        await file.parent.create(recursive: true);
        if (!await _validFile(file)) {
          final response = await _client
              .get(Uri.parse('$bibleAudioBaseUrl/$relative'))
              .timeout(const Duration(seconds: 45));
          if (!mounted || _cancelled.contains(book)) return;
          if (response.statusCode != 200 || !isMp3Header(response.bodyBytes)) {
            throw StateError(
              'Pasal $chapter gagal diunduh (HTTP ${response.statusCode}).',
            );
          }
          final temp = File('${file.path}.part');
          await temp.writeAsBytes(response.bodyBytes, flush: true);
          await temp.rename(file.path);
        }
        if (!mounted) return;
        setState(() => _downloadProgress[book] = chapter / total);
      }
      if (mounted)
        _showSnackBar('${_bookNames[index]} tersedia lengkap secara offline.');
    } catch (_) {
      if (mounted && !_cancelled.contains(book)) {
        _showSnackBar(
          'Unduhan belum lengkap. Ketuk lagi untuk melanjutkan pasal yang belum tersedia.',
        );
      }
    } finally {
      _busy.remove(book);
      if (root != null && mounted) {
        try {
          final count = await _countChapters(root, book);
          if (mounted)
            setState(() {
              _availableChapters[book] = count;
              _isDownloaded[book] = count == bibleChaptersPerBook[book];
            });
        } catch (_) {
          _showSnackBar('Status unduhan belum dapat diperiksa.');
        }
      }
      if (mounted) setState(() => _downloadProgress.remove(book));
    }
  }

  Future<void> _deleteBook(int index) async {
    final book = index + 1;
    if (_busy.contains(book)) return;
    _busy.add(book);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory(
        '${dir.path}/audio/${bibleAudioMap[book]!['folder']}',
      );
      if (await folder.exists()) await folder.delete(recursive: true);
      if (!mounted) return;
      setState(() {
        _isDownloaded[book] = false;
        _availableChapters[book] = 0;
      });
      _showSnackBar(
        'Audio offline ${_bookNames[index]} dihapus dari perangkat.',
      );
    } catch (_) {
      _showSnackBar('Audio belum dapat dihapus. Coba lagi.');
    } finally {
      _busy.remove(book);
    }
  }

  void _showSnackBar(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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
          bool isAvailableOnServer = bibleAudioMap.containsKey(bookNum);
          bool isDownloaded = _isDownloaded[bookNum] ?? false;
          double? progress = _downloadProgress[bookNum];

          return ListTile(
            title: Text(
              _bookNames[index],
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              !isAvailableOnServer
                  ? "Belum didaftarkan"
                  : isDownloaded
                  ? "Tersedia Offline"
                  : "${_availableChapters[bookNum] ?? 0}/${bibleChaptersPerBook[bookNum]} pasal tersedia; ketuk untuk mengunduh",
              style: TextStyle(
                color: !isAvailableOnServer
                    ? Colors.redAccent
                    : Colors.grey[600],
                fontStyle: !isAvailableOnServer
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
            trailing: !isAvailableOnServer
                ? const Icon(Icons.access_time, color: Colors.grey)
                : progress != null
                ? IconButton(
                    tooltip: 'Batalkan unduhan',
                    onPressed: () {
                      _cancelled.add(bookNum);
                      _showSnackBar(
                        'Unduhan dihentikan setelah request berjalan selesai.',
                      );
                    },
                    icon: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        value: progress,
                        color: Colors.indigo,
                      ),
                    ),
                  )
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
                _showSnackBar(
                  "Sudah diunduh. Tahan lama untuk menghapus dari HP.",
                );
              }
            },
            onLongPress: () {
              if (isAvailableOnServer && isDownloaded) _deleteBook(index);
            },
          );
        },
      ),
    );
  }
}
