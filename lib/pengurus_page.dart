import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_manager.dart';
import 'detail_seksi_page.dart';
import 'pengurus_repository.dart';
import 'pengurus_support.dart';
import 'pengurus_widgets.dart';

class PengurusPage extends StatefulWidget {
  final String? churchId;
  const PengurusPage({super.key, this.churchId});
  @override
  State<PengurusPage> createState() => _PengurusPageState();
}

class _PengurusPageState extends State<PengurusPage> {
  PengurusRepository? _repo;
  late final String _churchName;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _churchStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _seksiStream,
      _penasehatStream,
      _bpkStream;
  String _search = '';
  @override
  void initState() {
    super.initState();
    final user = UserManager();
    final id = (widget.churchId ?? user.getChurchIdForCurrentView())?.trim();
    _churchName = id == user.getChurchIdForCurrentView()
        ? user.activeChurchName ?? user.originalChurchName ?? 'Gereja'
        : 'Gereja pilihan';
    if (id != null && pengurusValidId(id) && user.userId != null) {
      _repo = PengurusRepository(
        id,
        user.userId!,
        readOnly:
            widget.churchId != null && id != user.getChurchIdForCurrentView(),
      );
      _connect();
    }
  }

  void _connect() {
    final church = _repo!.church;
    _churchStream = church.snapshots();
    _seksiStream = church.collection('bpj_seksi').snapshots();
    // Sort locally so legacy records without createdAt remain visible.
    _penasehatStream = church.collection('bpj_penasehat').snapshots();
    _bpkStream = church.collection('bpj_bpk').snapshots();
  }

  void _retry() {
    if (mounted && _repo != null) setState(_connect);
  }

  bool get _canEdit => _repo?.canEdit ?? false;
  bool _matches(String text) =>
      _search.isEmpty || text.toLowerCase().contains(_search);
  Future<void> _editSeksi({String? docId, String name = ''}) async {
    final repo = _repo;
    if (repo == null || !repo.canEdit) return;
    final doc = docId == null
        ? repo.church.collection('bpj_seksi').doc()
        : repo.church.collection('bpj_seksi').doc(docId);
    await showPengurusNameEditor(
      context,
      initialName: name,
      save: (value) async {
        await repo.checkAccess();
        if (docId == null) {
          await repo.db
              .runTransaction((tx) async {
                final parent = await tx.get(repo.church);
                final existing = await tx.get(doc);
                repo.checkSession();
                if (!parent.exists)
                  throw StateError('Gereja sudah tidak tersedia.');
                if (!existing.exists) tx.set(doc, {'namaSeksi': value});
              })
              .timeout(const Duration(seconds: 30));
        } else {
          await doc
              .update({'namaSeksi': value})
              .timeout(const Duration(seconds: 30));
        }
      },
      delete: docId == null
          ? null
          : () async {
              await repo.checkAccess();
              await doc.delete().timeout(const Duration(seconds: 30));
            },
    );
    if (mounted) setState(() {});
  }

  Future<void> _editInti(
    String roleId,
    String role,
    Map<String, dynamic> data,
  ) async {
    final repo = _repo;
    if (repo == null || !repo.canEdit) return;
    await showPengurusPersonEditor(
      context,
      title: 'Edit $role',
      name: pengurusText(data['bpj_$roleId']),
      wa: pengurusText(data['wa_$roleId']),
      photo: pengurusPhoto(data['img_$roleId']),
      save: (input) => repo.savePerson(
        repo.church,
        {'bpj_$roleId': input.name, 'wa_$roleId': input.wa},
        photoKey: 'img_$roleId',
        photo: input.photo,
        oldPhoto: pengurusText(data['img_$roleId']),
        removePhoto: input.removePhoto,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _editMember(
    String collection, {
    String? docId,
    Map<String, dynamic> data = const {},
  }) async {
    final repo = _repo;
    if (repo == null || !repo.canEdit) return;
    final doc = docId == null
        ? repo.church.collection(collection).doc()
        : repo.church.collection(collection).doc(docId);
    await showPengurusPersonEditor(
      context,
      title: docId == null ? 'Tambah anggota' : 'Edit anggota',
      name: pengurusText(data['nama']),
      wa: pengurusText(data['wa']),
      photo: pengurusPhoto(data['fotoUrl']),
      save: (input) => repo.saveDynamicPerson(
        doc,
        {'nama': input.name, 'wa': input.wa},
        create: docId == null,
        photo: input.photo,
        oldPhoto: pengurusText(data['fotoUrl']),
        removePhoto: input.removePhoto,
      ),
      delete: docId == null
          ? null
          : () async {
              await repo.checkAccess();
              await doc.delete().timeout(const Duration(seconds: 30));
            },
    );
    if (mounted) setState(() {});
  }

  void _openSeksi(String id, String name) {
    final repo = _repo!;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DetailSeksiPage(
          docId: id,
          namaSeksi: name,
          churchId: repo.churchId,
          readOnly: !repo.canEdit,
        ),
      ),
    );
  }

  Widget _card(
    String title,
    List<Widget> children, {
    VoidCallback? add,
    VoidCallback? edit,
    VoidCallback? open,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
          onTap: open,
          trailing: edit != null && _canEdit
              ? IconButton(
                  tooltip: 'Edit seksi',
                  onPressed: edit,
                  icon: const Icon(Icons.edit),
                )
              : open == null
              ? null
              : const Icon(Icons.chevron_right),
        ),
        ...children,
        if (add != null && _canEdit)
          TextButton.icon(
            onPressed: add,
            icon: const Icon(Icons.add),
            label: const Text('Tambah anggota'),
          ),
      ],
    ),
  );
  Widget _person(
    String role,
    String name,
    String? photo,
    String wa, {
    VoidCallback? edit,
    VoidCallback? open,
  }) {
    final empty = name.isEmpty || name == '-';
    return ListTile(
      leading: pengurusAvatar(photo),
      title: Text(empty ? 'Belum diatur' : name),
      subtitle: Text(role),
      onTap:
          open ??
          (empty
              ? edit
              : () => showPengurusDetail(context, name, role, photo, wa)),
      onLongPress: _canEdit ? edit : null,
      trailing: edit != null && _canEdit
          ? IconButton(
              tooltip: 'Edit $role',
              onPressed: edit,
              icon: const Icon(Icons.edit, size: 20),
            )
          : null,
    );
  }

  Widget _dynamic(
    String title,
    String collection,
    Stream<QuerySnapshot<Map<String, dynamic>>>? stream,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return _card(title, [
          pengurusMessage(pengurusError(snapshot.error!), retry: _retry),
        ]);
      if (!snapshot.hasData)
        return _card(title, [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ]);
      final docs = snapshot.data!.docs.toList()
        ..sort((a, b) {
          final at = a.data()['createdAt'], bt = b.data()['createdAt'];
          final timeA = at is Timestamp ? at.millisecondsSinceEpoch : 0;
          final timeB = bt is Timestamp ? bt.millisecondsSinceEpoch : 0;
          final order = timeA.compareTo(timeB);
          return order == 0 ? a.id.compareTo(b.id) : order;
        });
      final rows = <Widget>[];
      for (final doc in docs) {
        final data = doc.data();
        final name = pengurusText(data['nama']);
        if (!_matches('$title $name')) continue;
        rows.add(
          _person(
            title,
            name,
            pengurusPhoto(data['fotoUrl']),
            pengurusText(data['wa']),
            edit: () => _editMember(collection, docId: doc.id, data: data),
          ),
        );
      }
      return _card(
        title,
        rows.isEmpty
            ? [
                pengurusMessage(
                  _search.isEmpty ? 'Belum ada anggota.' : 'Tidak ada hasil.',
                ),
              ]
            : rows,
        add: () => _editMember(collection),
      );
    },
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FA),
    appBar: AppBar(
      title: const Text('Badan Pengurus Jemaat'),
      backgroundColor: Colors.indigo[900],
      foregroundColor: Colors.white,
    ),
    body: _repo == null
        ? pengurusMessage(
            'Gereja atau sesi akun belum tersedia. Silakan kembali dan masuk ulang.',
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _churchStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return pengurusMessage(
                      pengurusError(snapshot.error!),
                      retry: _retry,
                    );
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  if (!snapshot.data!.exists)
                    return pengurusMessage(
                      snapshot.data!.metadata.isFromCache
                          ? 'Data gereja belum tersedia di perangkat. Sambungkan internet dan coba lagi.'
                          : 'Gereja sudah tidak tersedia.',
                      retry: snapshot.data!.metadata.isFromCache
                          ? _retry
                          : null,
                    );
                  final data = snapshot.data!.data() ?? <String, dynamic>{};
                  final name = pengurusText(data['namaGereja']);
                  Widget group(
                    String title,
                    Map<String, String> roles,
                  ) => _card(title, [
                    for (final entry in roles.entries)
                      if (_matches(
                        '${entry.value} ${pengurusText(data['bpj_${entry.key}'])}',
                      ))
                        _person(
                          entry.value,
                          pengurusText(data['bpj_${entry.key}']),
                          pengurusPhoto(data['img_${entry.key}']),
                          pengurusText(data['wa_${entry.key}']),
                          edit: _canEdit
                              ? () => _editInti(entry.key, entry.value, data)
                              : null,
                        ),
                  ]);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        name.isEmpty ? _churchName : name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      if (!_canEdit)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Hanya lihat • perubahan tidak diizinkan',
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        onChanged: (value) => setState(
                          () => _search = value.trim().toLowerCase(),
                        ),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Cari pengurus atau seksi',
                        ),
                      ),
                      const SizedBox(height: 16),
                      group('Pimpinan', {
                        'ketua': 'KETUA BPJ',
                        'wakil': 'WAKIL KETUA',
                      }),
                      group('Sekretariat', {
                        'sek1': 'SEKRETARIS 1',
                        'sek2': 'SEKRETARIS 2',
                      }),
                      group('Kebendaharaan', {
                        'bend1': 'BENDAHARA 1',
                        'bend2': 'BENDAHARA 2',
                      }),
                    ],
                  );
                },
              ),
              _dynamic('Penasehat', 'bpj_penasehat', _penasehatStream),
              _dynamic('Badan Pemeriksa Keuangan (BPK)', 'bpj_bpk', _bpkStream),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'SEKSI & KOMISI',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _seksiStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return pengurusMessage(
                      pengurusError(snapshot.error!),
                      retry: _retry,
                    );
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final docs = snapshot.data!.docs.toList()
                    ..sort(
                      (a, b) => pengurusText(a.data()['namaSeksi'])
                          .toLowerCase()
                          .compareTo(
                            pengurusText(b.data()['namaSeksi']).toLowerCase(),
                          ),
                    );
                  final rows = <Widget>[];
                  for (final doc in docs) {
                    final data = doc.data();
                    final name = pengurusText(data['namaSeksi']);
                    final chair = pengurusText(
                      data['ketua_nama'] ?? data['namaPengurus'],
                    );
                    if (!_matches('$name $chair')) continue;
                    rows.add(
                      _card(
                        name.isEmpty ? 'Seksi' : name,
                        [
                          _person(
                            'KETUA',
                            chair,
                            pengurusPhoto(data['ketua_img'] ?? data['fotoUrl']),
                            pengurusText(data['ketua_wa'] ?? data['telepon']),
                            open: () => _openSeksi(doc.id, name),
                          ),
                        ],
                        open: () => _openSeksi(doc.id, name),
                        edit: () => _editSeksi(docId: doc.id, name: name),
                      ),
                    );
                  }
                  return rows.isEmpty
                      ? pengurusMessage(
                          _search.isEmpty
                              ? 'Belum ada data seksi.'
                              : 'Tidak ada seksi yang cocok.',
                        )
                      : Column(children: rows);
                },
              ),
              const SizedBox(height: 80),
            ],
          ),
    floatingActionButton: _canEdit
        ? FloatingActionButton.extended(
            onPressed: _editSeksi,
            icon: const Icon(Icons.add_business),
            label: const Text('Tambah seksi'),
          )
        : null,
  );
}
