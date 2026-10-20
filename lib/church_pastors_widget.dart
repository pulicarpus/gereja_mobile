import 'pastor_profile_page.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'church_pastors.dart';
import 'pengurus_widgets.dart';
import 'upload_support.dart';
import 'user_manager.dart';

class ChurchPastorsSection extends StatefulWidget {
  final String? churchId;
  const ChurchPastorsSection({super.key, required this.churchId});
  @override
  State<ChurchPastorsSection> createState() => _ChurchPastorsSectionState();
}

class _ChurchPastorsSectionState extends State<ChurchPastorsSection> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _stream;
  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(covariant ChurchPastorsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.churchId != widget.churchId) _connect();
  }

  void _connect() {
    _stream = widget.churchId == null
        ? null
        : FirebaseFirestore.instance
              .collection('churches')
              .doc(widget.churchId)
              .snapshots();
  }

  Future<void> _edit(ChurchPastor? profile) async {
    final id = widget.churchId;
    if (id == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PastorEditor(
        repository: ChurchPastorsRepository(id),
        profile: profile,
      ),
    );
  }

  Future<void> _remove(ChurchPastor profile) async {
    final id = widget.churchId;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Hapus profil gembala?'),
        content: Text(
          'Hapus profil ${profile.name} dari halaman utama? Data jemaat dan akun tetap tersimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Hapus profil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ChurchPastorsRepository(id).remove(profile);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(pengurusError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = UserManager().isAdmin();
    if (widget.churchId == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return pengurusMessage(pengurusError(snapshot.error!));
        if (snapshot.connectionState == ConnectionState.waiting ||
            !snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        if (!snapshot.data!.exists) return const SizedBox.shrink();
        final profiles = churchPastors(snapshot.data!.data()!);
        if (profiles.isEmpty && !canEdit) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Gembala Sidang',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (canEdit)
                  IconButton(
                    tooltip: 'Tambah gembala',
                    onPressed: () => _edit(null),
                    icon: const Icon(
                      Icons.person_add_alt_1,
                      color: Colors.indigo,
                    ),
                  ),
              ],
            ),
            if (profiles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Belum ada profil gembala. Ketuk tambah untuk mengisi.',
                ),
              ),
            for (final profile in profiles)
              Card(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                child: InkWell(
                  onTap: () => openPastorProfile(
                    context,
                    profile,
                    widget.churchId!,
                    UserManager().activeChurchName ??
                        UserManager().originalChurchName ??
                        'Gereja',
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ChurchPastorAvatar(
                              pastor: profile,
                              churchId: widget.churchId!,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                profile.name,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (canEdit)
                              PopupMenuButton<String>(
                                tooltip: 'Atur ${profile.name}',
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit profil'),
                                  ),
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: Text('Hapus profil'),
                                  ),
                                ],
                                onSelected: (action) => action == 'edit'
                                    ? _edit(profile)
                                    : _remove(profile),
                              ),
                          ],
                        ),
                        Wrap(
                          spacing: 4,
                          children: [
                            if (profile.wa.isNotEmpty)
                              IconButton(
                                tooltip: 'WhatsApp',
                                icon: const Icon(
                                  Icons.phone,
                                  color: Colors.green,
                                ),
                                onPressed: () =>
                                    pengurusWhatsApp(context, profile.wa),
                              ),
                            for (final entry in [
                              (profile.fb, Icons.facebook, 'Facebook'),
                              (profile.ig, Icons.camera_alt, 'Instagram'),
                              (profile.tiktok, Icons.music_note, 'TikTok'),
                              (profile.yt, Icons.play_circle_fill, 'YouTube'),
                            ])
                              if (entry.$1.isNotEmpty)
                                IconButton(
                                  tooltip: entry.$3,
                                  icon: Icon(entry.$2, color: Colors.indigo),
                                  onPressed: () =>
                                      openPastorLink(context, entry.$1),
                                ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PastorEditor extends StatefulWidget {
  final ChurchPastorsRepository repository;
  final ChurchPastor? profile;
  const _PastorEditor({required this.repository, this.profile});
  @override
  State<_PastorEditor> createState() => _PastorEditorState();
}

class _PastorEditorState extends State<_PastorEditor> {
  final _form = GlobalKey<FormState>();
  late final String _id = widget.profile?.id ?? widget.repository.newId();
  late final Map<String, TextEditingController> _fields = {
    for (final entry in {
      'name': widget.profile?.name,
      'wa': widget.profile?.wa,
      'fb': widget.profile?.fb,
      'ig': widget.profile?.ig,
      'tiktok': widget.profile?.tiktok,
      'yt': widget.profile?.yt,
    }.entries)
      entry.key: TextEditingController(text: entry.value ?? ''),
  };
  File? _photo;
  String? _uploadedPhoto, _error;
  bool _saving = false, _picking = false;
  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    if (_saving || _picking) return;
    setState(() => _picking = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (file != null && mounted)
        setState(() {
          _photo = File(file.path);
          _uploadedPhoto = null;
        });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Foto belum dapat dibuka. Coba lagi.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _picking || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.checkAccess();
      if (_photo != null && _uploadedPhoto == null) {
        final ref = FirebaseStorage.instance.ref(
          'gereja/${widget.repository.churchId}/gembala/$_id/${DateTime.now().microsecondsSinceEpoch}.jpg',
        );
        final task = ref.putFile(_photo!, await prepareUpload(_photo!));
        try {
          await task.timeout(const Duration(seconds: 30));
        } on TimeoutException {
          await task.cancel();
          rethrow;
        }
        _uploadedPhoto = await ref.getDownloadURL().timeout(
          const Duration(seconds: 20),
        );
      }
      final profile = ChurchPastor.fromMap({
        'id': _id,
        for (final entry in _fields.entries) entry.key: entry.value.text.trim(),
        'photo': _uploadedPhoto ?? widget.profile?.photo ?? '',
      });
      await widget.repository.save(profile, expected: widget.profile);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = pengurusError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && !_picking,
    child: AlertDialog(
      title: Text(
        widget.profile == null ? 'Tambah Gembala' : 'Edit Profil Gembala',
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: _saving || _picking ? null : _pick,
                child: _photo != null
                    ? CircleAvatar(
                        radius: 45,
                        backgroundImage: FileImage(_photo!),
                      )
                    : pengurusAvatar(
                        widget.profile?.photo.isNotEmpty == true
                            ? widget.profile!.photo
                            : null,
                        radius: 45,
                      ),
              ),
              TextButton(
                onPressed: _saving || _picking ? null : _pick,
                child: Text(_picking ? 'Membuka foto…' : 'Pilih foto'),
              ),
              for (final entry in const {
                'name': 'Nama gembala',
                'wa': 'WhatsApp (opsional)',
                'fb': 'Link Facebook',
                'ig': 'Link Instagram',
                'tiktok': 'Link TikTok',
                'yt': 'Link YouTube',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: _fields[entry.key],
                    enabled: !_saving && !_picking,
                    decoration: InputDecoration(
                      labelText: entry.value,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: entry.key == 'wa'
                        ? TextInputType.phone
                        : TextInputType.text,
                    maxLength: entry.key == 'name' ? 160 : 2048,
                    validator: (value) =>
                        entry.key == 'name' && (value?.trim().isEmpty ?? true)
                        ? 'Nama wajib diisi.'
                        : null,
                  ),
                ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              if (_saving) const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving || _picking ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving || _picking ? null : _save,
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
}
