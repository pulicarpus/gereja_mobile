import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_manager.dart';
import 'pengurus_repository.dart';
import 'pengurus_support.dart';
import 'pengurus_widgets.dart';

class DetailSeksiPage extends StatefulWidget {
  final String docId, namaSeksi;
  final String? churchId;
  final String? namaDaerah;
  final bool readOnly;
  const DetailSeksiPage({
    super.key,
    required this.docId,
    required this.namaSeksi,
    this.churchId,
    this.namaDaerah,
    this.readOnly = false,
  });
  @override
  State<DetailSeksiPage> createState() => _DetailSeksiPageState();
}

class _DetailSeksiPageState extends State<DetailSeksiPage> {
  PengurusRepository? _repo;
  DocumentReference<Map<String, dynamic>>? _doc;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _stream;
  bool _deleting = false;
  @override
  void initState() {
    super.initState();
    final user = UserManager();
    final id = widget.namaDaerah != null
        ? Uri.encodeComponent(widget.namaDaerah!.trim())
        : (widget.churchId ?? user.getChurchIdForCurrentView())?.trim();
    if (id != null &&
        pengurusValidId(id) &&
        user.userId != null &&
        pengurusValidId(widget.docId)) {
      _repo = widget.namaDaerah != null
          ? PengurusRepository.daerah(
              widget.namaDaerah!,
              user.userId!,
              readOnly: widget.readOnly,
              documentId: widget.churchId,
            )
          : PengurusRepository(
              id,
              user.userId!,
              readOnly:
                  widget.readOnly || id != user.getChurchIdForCurrentView(),
            );
      _doc = _repo!.church.collection(_repo!.seksiCollection).doc(widget.docId);
      _stream = _doc!.snapshots();
    }
  }

  void _retry() {
    if (mounted && _doc != null) setState(() => _stream = _doc!.snapshots());
  }

  bool get _canEdit => !_deleting && (_repo?.canEdit ?? false);
  Future<void> _editRole(
    String role,
    String label,
    Map<String, dynamic> data,
  ) async {
    if (!_canEdit) return;
    final name = pengurusText(
      data['${role}_nama'] ?? (role == 'ketua' ? data['namaPengurus'] : null),
    );
    final wa = pengurusText(
      data['${role}_wa'] ?? (role == 'ketua' ? data['telepon'] : null),
    );
    final photo = pengurusText(
      data['${role}_img'] ?? (role == 'ketua' ? data['fotoUrl'] : null),
    );
    await showPengurusPersonEditor(
      context,
      title: 'Edit $label',
      name: name,
      wa: wa,
      photo: pengurusPhoto(photo),
      save: (input) => _repo!.savePerson(
        _doc!,
        {
          '${role}_nama': input.name,
          '${role}_wa': input.wa,
          if (role == 'ketua' && data.containsKey('namaPengurus'))
            'namaPengurus': input.name,
          if (role == 'ketua' && data.containsKey('telepon'))
            'telepon': input.wa,
        },
        photoKey: '${role}_img',
        mirrorPhotoKey: role == 'ketua' && data.containsKey('fotoUrl')
            ? 'fotoUrl'
            : null,
        photo: input.photo,
        oldPhoto: photo,
        removePhoto: input.removePhoto,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _editMember(List<dynamic> original, {int? index}) async {
    if (!_canEdit) return;
    final data = index == null
        ? <String, dynamic>{}
        : pengurusMember(original[index]);
    final operationId = _repo!.church
        .collection(_repo!.seksiCollection)
        .doc()
        .id;
    await showPengurusPersonEditor(
      context,
      title: index == null ? 'Tambah anggota' : 'Edit anggota',
      name: pengurusText(data['nama']),
      wa: pengurusText(data['wa']),
      photo: pengurusPhoto(data['img']),
      save: (input) => _repo!.changeMember(
        _doc!,
        original,
        index,
        {...data, 'nama': input.name, 'wa': input.wa},
        photo: input.photo,
        oldPhoto: pengurusText(data['img']),
        removePhoto: input.removePhoto,
        operationId: operationId,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _remove(List<dynamic> original, int index) async {
    if (!_canEdit) return;
    final name = pengurusText(pengurusMember(original[index])['nama']);
    setState(() => _deleting = true);
    final confirmed = await confirmPengurusDelete(
      context,
      'Hapus anggota $name?',
    );
    if (!mounted) return;
    if (!confirmed) {
      setState(() => _deleting = false);
      return;
    }
    try {
      await _repo!.changeMember(_doc!, original, index, null, operationId: '');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Anggota dihapus.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(pengurusError(e))));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _person(
    String name,
    String label,
    String? photo,
    String wa, {
    VoidCallback? edit,
    VoidCallback? delete,
  }) => Card(
    child: ListTile(
      leading: pengurusAvatar(photo),
      title: Text(name.isEmpty ? 'Belum diatur' : name),
      subtitle: Text(label),
      onTap: name.isEmpty
          ? edit
          : () => showPengurusDetail(context, name, label, photo, wa),
      onLongPress: edit,
      trailing: edit == null && delete == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (edit != null)
                  IconButton(
                    tooltip: 'Edit $label',
                    onPressed: edit,
                    icon: const Icon(Icons.edit, size: 20),
                  ),
                if (delete != null)
                  IconButton(
                    tooltip: 'Hapus anggota',
                    onPressed: delete,
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                  ),
              ],
            ),
    ),
  );
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _stream,
    builder: (context, snapshot) {
      final data = snapshot.data?.data() ?? <String, dynamic>{};
      final liveName = pengurusText(data[_repo?.sectionNameKey ?? 'namaSeksi']);
      final name = liveName.isEmpty ? widget.namaSeksi : liveName;
      Widget body;
      if (_repo == null) {
        body = pengurusMessage(
          'Gereja atau sesi akun belum tersedia. Silakan kembali.',
        );
      } else if (snapshot.hasError) {
        body = pengurusMessage(pengurusError(snapshot.error!), retry: _retry);
      } else if (!snapshot.hasData) {
        body = const Center(child: CircularProgressIndicator());
      } else if (!snapshot.data!.exists) {
        body = pengurusMessage(
          snapshot.data!.metadata.isFromCache
              ? 'Data seksi belum tersedia di perangkat. Sambungkan internet dan coba lagi.'
              : 'Seksi sudah dihapus. Silakan kembali ke daftar Pengurus.',
          retry: snapshot.data!.metadata.isFromCache ? _retry : null,
        );
      } else {
        final members = pengurusMembers(data['anggota']);
        Widget role(String id, String label) {
          final person = pengurusText(
            data['${id}_nama'] ?? (id == 'ketua' ? data['namaPengurus'] : null),
          );
          return _person(
            person,
            label,
            pengurusPhoto(
              data['${id}_img'] ?? (id == 'ketua' ? data['fotoUrl'] : null),
            ),
            pengurusText(
              data['${id}_wa'] ?? (id == 'ketua' ? data['telepon'] : null),
            ),
            edit: _canEdit ? () => _editRole(id, label, data) : null,
          );
        }

        body = ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_canEdit && !_deleting)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text('Hanya lihat • perubahan tidak diizinkan'),
              ),
            const Text(
              'PENGURUS HARIAN',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            role('ketua', 'KETUA'),
            if (_canEdit || pengurusText(data['sek_nama']).isNotEmpty)
              role('sek', 'SEKRETARIS'),
            if (_canEdit || pengurusText(data['bend_nama']).isNotEmpty)
              role('bend', 'BENDAHARA'),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'ANGGOTA',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (_canEdit)
                  TextButton.icon(
                    onPressed: () => _editMember(members),
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah'),
                  ),
              ],
            ),
            if (_deleting) const Center(child: CircularProgressIndicator()),
            if (members.isEmpty) pengurusMessage('Belum ada anggota.'),
            for (var i = 0; i < members.length; i++)
              _person(
                pengurusText(pengurusMember(members[i])['nama']),
                'Anggota $name',
                pengurusPhoto(pengurusMember(members[i])['img']),
                pengurusText(pengurusMember(members[i])['wa']),
                edit: _canEdit ? () => _editMember(members, index: i) : null,
                delete: _canEdit ? () => _remove(members, i) : null,
              ),
          ],
        );
      }
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: Text('Struktur $name'),
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
        ),
        body: body,
      );
    },
  );
}
