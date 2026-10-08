import 'dart:io';
import 'package:flutter/material.dart';
import 'pengurus_support.dart';

Widget regionPhoto({String? url, File? file, bool thumbnail = false}) {
  final remote = pengurusPhoto(url);
  Widget fallback() => ColoredBox(
    color: Colors.indigo.shade50,
    child: const Center(
      child: Icon(Icons.photo_outlined, color: Colors.indigo),
    ),
  );
  final image = file != null
      ? Image.file(
          file,
          fit: thumbnail ? BoxFit.cover : BoxFit.contain,
          errorBuilder: (_, __, ___) => fallback(),
        )
      : remote != null
      ? Image.network(
          remote,
          fit: thumbnail ? BoxFit.cover : BoxFit.contain,
          errorBuilder: (_, __, ___) => fallback(),
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        )
      : fallback();
  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: thumbnail
        ? SizedBox(width: 48, height: 48, child: image)
        : SizedBox(width: double.infinity, height: 190, child: image),
  );
}
