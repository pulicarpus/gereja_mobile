import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pengurus_support.dart';

String pengurusError(Object error) {
  if (error is TimeoutException)
    return 'Koneksi terlalu lama. Hasil simpan belum dapat dipastikan; periksa data terbaru sebelum mencoba lagi.';
  if (error is FirebaseException) {
    if (error.code == 'permission-denied')
      return 'Akses ditolak. Periksa izin akun Anda.';
    if (error.code == 'not-found')
      return 'Data sudah dihapus. Buka kembali halaman ini.';
    return 'Operasi gagal. Periksa koneksi lalu coba lagi.';
  }
  if (error is StateError) return error.message.toString();
  return 'Operasi gagal. Silakan coba lagi.';
}

Widget pengurusMessage(String message, {VoidCallback? retry}) => Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(message, textAlign: TextAlign.center),
      if (retry != null)
        TextButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Coba lagi'),
        ),
    ],
  ),
);
Widget pengurusAvatar(String? photo, {double radius = 25}) => ClipOval(
  child: SizedBox(
    width: radius * 2,
    height: radius * 2,
    child: photo == null
        ? ColoredBox(
            color: Colors.indigo.shade50,
            child: Icon(Icons.person, size: radius, color: Colors.indigo),
          )
        : CachedNetworkImage(
            imageUrl: photo,
            fit: BoxFit.cover,
            placeholder: (_, __) =>
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            errorWidget: (_, __, ___) => ColoredBox(
              color: Colors.indigo.shade50,
              child: Icon(Icons.person, size: radius, color: Colors.indigo),
            ),
          ),
  ),
);

Future<void> pengurusWhatsApp(BuildContext context, String raw) async {
  final number = pengurusWa(raw);
  if (number == null) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nomor WhatsApp belum tersedia atau tidak valid.'),
        ),
      );
    return;
  }
  try {
    final opened = await launchUrl(
      Uri.https('wa.me', '/$number'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak dapat membuka WhatsApp.')),
      );
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak dapat membuka WhatsApp.')),
      );
  }
}

void showPengurusDetail(
  BuildContext context,
  String name,
  String role,
  String? photo,
  String wa,
) {
  final pageContext = context;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
    ),
    builder: (sheetContext) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: photo == null
                  ? null
                  : () => Navigator.of(sheetContext).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          backgroundColor: Colors.black,
                          appBar: AppBar(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                          ),
                          body: Center(
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 4,
                              child: CachedNetworkImage(
                                imageUrl: photo,
                                fit: BoxFit.contain,
                                errorWidget: (_, __, ___) => const Icon(
                                  Icons.broken_image,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              child: pengurusAvatar(photo, radius: 50),
            ),
            const SizedBox(height: 16),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Text(role, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: pengurusWa(wa) == null
                  ? null
                  : () {
                      Navigator.pop(sheetContext);
                      pengurusWhatsApp(pageContext, wa);
                    },
              icon: const Icon(Icons.chat),
              label: const Text('Hubungi via WhatsApp'),
            ),
            if (pengurusWa(wa) == null)
              const Text('Nomor WhatsApp belum tersedia atau tidak valid.'),
          ],
        ),
      ),
    ),
  );
}

class PengurusPersonInput {
  final String name, wa;
  final File? photo;
  final bool removePhoto;
  PengurusPersonInput(this.name, this.wa, this.photo, this.removePhoto);
}

Future<void> showPengurusPersonEditor(
  BuildContext context, {
  required String title,
  String name = '',
  String wa = '',
  String? photo,
  required Future<void> Function(PengurusPersonInput) save,
  Future<void> Function()? delete,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _PersonEditor(
    title: title,
    name: name,
    wa: wa,
    photo: photo,
    save: save,
    delete: delete,
  ),
);

class _PersonEditor extends StatefulWidget {
  final String title, name, wa;
  final String? photo;
  final Future<void> Function(PengurusPersonInput) save;
  final Future<void> Function()? delete;
  const _PersonEditor({
    required this.title,
    required this.name,
    required this.wa,
    required this.photo,
    required this.save,
    this.delete,
  });
  @override
  State<_PersonEditor> createState() => _PersonEditorState();
}

class _PersonEditorState extends State<_PersonEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name,
  );
  late final TextEditingController _wa = TextEditingController(text: widget.wa);
  File? _photo;
  bool _removePhoto = false,
      _busy = false,
      _picking = false,
      _uncertain = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _wa.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_busy || _picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (mounted && picked != null)
        setState(() {
          _photo = File(picked.path);
          _removePhoto = false;
        });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Foto tidak dapat dipilih. Silakan coba lagi.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit({bool deleting = false}) async {
    if (_busy || _picking || _uncertain) return;
    final name = _name.text.trim(), wa = _wa.text.trim();
    if (!deleting &&
        (name.isEmpty || (wa.isNotEmpty && pengurusWa(wa) == null))) {
      setState(
        () => _error = name.isEmpty
            ? 'Nama wajib diisi.'
            : 'Nomor WhatsApp tidak valid.',
      );
      return;
    }
    if (deleting) {
      setState(() => _busy = true);
      final confirmed = await confirmPengurusDelete(
        context,
        'Hapus ${widget.name}?',
      );
      if (!mounted) return;
      if (!confirmed) {
        setState(() => _busy = false);
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (deleting) {
        await widget.delete!();
      } else {
        await widget.save(
          PengurusPersonInput(
            name,
            wa.isEmpty ? '' : pengurusWa(wa)!,
            _photo,
            _removePhoto,
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = pengurusError(e);
          _uncertain = e is TimeoutException;
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_picking,
    child: AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _busy || _picking ? null : _pick,
              child: _photo == null
                  ? pengurusAvatar(
                      _removePhoto ? null : widget.photo,
                      radius: 40,
                    )
                  : ClipOval(
                      child: Image.file(
                        _photo!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
            ),
            TextButton(
              onPressed: _busy || _picking ? null : _pick,
              child: Text(_picking ? 'Memilih foto…' : 'Pilih foto'),
            ),
            if (_photo != null || (!_removePhoto && widget.photo != null))
              TextButton(
                onPressed: _busy || _picking
                    ? null
                    : () => setState(() {
                        _photo = null;
                        _removePhoto = true;
                      }),
                child: const Text('Hapus foto'),
              ),
            TextField(
              controller: _name,
              enabled: !_busy && !_picking,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Nama'),
            ),
            TextField(
              controller: _wa,
              enabled: !_busy && !_picking,
              keyboardType: TextInputType.phone,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: 'WhatsApp (opsional)',
              ),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
      actions: [
        if (widget.delete != null)
          TextButton(
            onPressed: _busy || _picking || _uncertain
                ? null
                : () => _submit(deleting: true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: _busy || _picking ? null : () => Navigator.pop(context),
          child: Text(_uncertain ? 'Tutup' : 'Batal'),
        ),
        ElevatedButton(
          onPressed: _busy || _picking || _uncertain ? null : _submit,
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
}

Future<bool> confirmPengurusDelete(
  BuildContext context,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Konfirmasi hapus'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    ) ??
    false;

Future<void> showPengurusNameEditor(
  BuildContext context, {
  required String initialName,
  required Future<void> Function(String) save,
  Future<void> Function()? delete,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      _NameEditor(initialName: initialName, save: save, delete: delete),
);

class _NameEditor extends StatefulWidget {
  final String initialName;
  final Future<void> Function(String) save;
  final Future<void> Function()? delete;
  const _NameEditor({
    required this.initialName,
    required this.save,
    this.delete,
  });
  @override
  State<_NameEditor> createState() => _NameEditorState();
}

class _NameEditorState extends State<_NameEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  bool _busy = false, _uncertain = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit({bool deleting = false}) async {
    if (_busy || _uncertain) return;
    if (!deleting && _name.text.trim().isEmpty) {
      setState(() => _error = 'Nama seksi wajib diisi.');
      return;
    }
    if (deleting) {
      setState(() => _busy = true);
      final confirmed = await confirmPengurusDelete(
        context,
        'Hapus seksi ${widget.initialName} beserta struktur dan daftar anggotanya?',
      );
      if (!mounted) return;
      if (!confirmed) {
        setState(() => _busy = false);
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (deleting) {
        await widget.delete!();
      } else {
        await widget.save(_name.text.trim());
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = pengurusError(e);
          _uncertain = e is TimeoutException;
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.delete == null ? 'Tambah seksi' : 'Edit nama seksi'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              enabled: !_busy,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Nama seksi/komisi'),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_busy) const CircularProgressIndicator(),
          ],
        ),
      ),
      actions: [
        if (widget.delete != null)
          TextButton(
            onPressed: _busy || _uncertain
                ? null
                : () => _submit(deleting: true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(_uncertain ? 'Tutup' : 'Batal'),
        ),
        ElevatedButton(
          onPressed: _busy || _uncertain ? null : _submit,
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
}
