import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class TelegramGalleryCache {
  static const String _prefix = "GKII_GALLERY_";

  static String _safeKey(String fileId) {
    final encoded = base64UrlEncode(utf8.encode(fileId)).replaceAll("=", "");
    return encoded.length > 160 ? encoded.substring(0, 160) : encoded;
  }

  static Future<File> fileFor(String fileId) async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/$_prefix${_safeKey(fileId)}.jpg');
  }

  static Future<File> getOrDownload({
    required String fileId,
    required String botToken,
  }) async {
    if (fileId.trim().isEmpty) {
      throw const FormatException("File ID kosong");
    }
    if (botToken.trim().isEmpty) {
      throw const FormatException("Bot token belum tersedia");
    }

    final file = await fileFor(fileId);
    if (await file.exists()) {
      final length = await file.length();
      if (length > 0) return file;
      await file.delete();
    }

    final infoResponse = await http
        .get(
          Uri.parse(
            "https://api.telegram.org/bot$botToken/getFile?file_id=${Uri.encodeQueryComponent(fileId)}",
          ),
        )
        .timeout(const Duration(seconds: 20));

    if (infoResponse.statusCode < 200 || infoResponse.statusCode >= 300) {
      throw HttpException("Telegram getFile gagal: ${infoResponse.statusCode}");
    }

    final decoded = jsonDecode(infoResponse.body);
    if (decoded is! Map || decoded['ok'] != true) {
      throw const FormatException("Respons Telegram tidak valid");
    }

    final result = decoded['result'];
    if (result is! Map) {
      throw const FormatException("Data file Telegram tidak valid");
    }

    final filePath = result['file_path']?.toString().trim() ?? "";
    if (filePath.isEmpty) {
      throw const FormatException("File path Telegram kosong");
    }

    final imageResponse = await http
        .get(
          Uri.parse("https://api.telegram.org/file/bot$botToken/$filePath"),
        )
        .timeout(const Duration(seconds: 30));

    if (imageResponse.statusCode < 200 || imageResponse.statusCode >= 300) {
      throw HttpException(
        "Download foto gagal: ${imageResponse.statusCode}",
      );
    }
    if (imageResponse.bodyBytes.isEmpty) {
      throw const FormatException("File foto kosong");
    }

    final tempFile = File("${file.path}.tmp");
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await tempFile.writeAsBytes(imageResponse.bodyBytes, flush: true);

    if (await file.exists()) {
      await file.delete();
    }
    return tempFile.rename(file.path);
  }

  static Future<void> deleteCached(String fileId) async {
    try {
      final file = await fileFor(fileId);
      if (await file.exists()) await file.delete();
      final tempFile = File("${file.path}.tmp");
      if (await tempFile.exists()) await tempFile.delete();
    } catch (_) {}
  }

  static Future<int> clearAll() async {
    final dir = await getTemporaryDirectory();
    var deleted = 0;

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isEmpty
          ? ""
          : entity.uri.pathSegments.last;
      final isGalleryCache =
          name.startsWith(_prefix) || name.startsWith("IMG_");
      if (!isGalleryCache) continue;

      try {
        await entity.delete();
        deleted++;
      } catch (_) {}
    }
    return deleted;
  }
}
