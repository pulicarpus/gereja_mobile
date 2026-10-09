import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_manager.dart';
import 'detail_seksi_page.dart';
import 'pengurus_repository.dart';
import 'pengurus_support.dart';
import 'pengurus_widgets.dart';
import 'daerah_records_page.dart';
import 'app_safety.dart';

class PengurusPage extends StatefulWidget {
  final String? churchId;
  final String? namaDaerah;
  const PengurusPage({super.key, this.churchId, this.namaDaerah});
  @override
  State<PengurusPage> createState() => _PengurusPageState();
}

class _PengurusPageState extends State<PengurusPage> {
  PengurusRepository? _repo;
  late final String _churchName;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _churchStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _seksiStream,
      _penasehatStream,
      _bpkStream,
      _mkdpStream;
  String _search = '';
  bool get _isRegion => widget.namaDaerah != null;
  String get _sectionLabel => _isRegion ? 'komisi' : 'seksi';
  @override
  void initState() {
    super.initState();
    final user = UserManager();
    final id = _isRegion
        ? Uri.encodeComponent(widget.namaDaerah!.trim())
        : (widget.churchId ?? user.getChurchIdForCurrentView())?.trim();
    _churchName = _isRegion
        ? widget.namaDaerah!
        : id == user.getChurchIdForCurrentView()
        ? user.activeChurchName ?? user.originalChurchName ?? 'Gereja'
        : 'Gereja pilihan';
    if (id != null && pengurusValidId(id) && user.userId != null) {
      _repo = _isRegion
          ? PengurusRepository.daerah(widget.namaDaerah!, user.userId!)
          : PengurusRepository(
              id,
              user.userId!,
              readOnly:
                  widget.churchId != null &&
                  id != user.getChurchIdForCurrentView(),
            );
      _connect();
    }
  }

  void _connect() {
    final church = _repo!.church;
    _churchStream = church.snapshots();
    _seksiStream = church.collection(_repo!.seksiCollection).snapshots();
    // Sort locally so legacy records without createdAt remain visible.
    _penasehatStream = church
        .collection(_isRegion ? 'penasehat' : 'bpj_penasehat')
        .snapshots();
    _bpkStream = church.collection(_isRegion ? 'bpk' : 'bpj_bpk').snapshots();
    if (_isRegion) _mkdpStream = church.collection('mkdp').snapshots();
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
        ? repo.church.collection(_repo!.seksiCollection).doc()
        : repo.church.collection(_repo!.seksiCollection).doc(docId);
    await showPengurusNameEditor(
      context,
      initialName: name,
      kind: _sectionLabel,
      save: (value) async {
        await repo.checkAccess();
        if (repo.isRegion) {
          await saveRegionChanges(
            repo.regionName!,
            {
              if (docId == null) repo.church: {'daerah': repo.regionName},
              doc: {repo.sectionNameKey: value, 'daerah': repo.regionName},
            },
            createOnly: docId == null,
            requireExisting: docId != null,
            allowPastors: false,
          );
          return;
        }
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
              if (repo.isRegion) {
                await saveRegionChanges(repo.regionName!, {
                  doc: null,
                }, allowPastors: false);
              } else {
                await doc.delete().timeout(const Duration(seconds: 30));
              }
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
      name: pengurusText(data['${repo.corePrefix}_$roleId']),
      wa: pengurusText(data['wa_$roleId']),
      photo: pengurusPhoto(data['img_$roleId']),
      save: (input) => repo.savePerson(
        repo.church,
        {'${repo.corePrefix}_$roleId': input.name, 'wa_$roleId': input.wa},
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
              if (repo.isRegion) {
                await saveRegionChanges(repo.regionName!, {
                  doc: null,
                }, allowPastors: false);
              } else {
                await doc.delete().timeout(const Duration(seconds: 30));
              }
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
          namaDaerah: widget.namaDaerah,
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
                  tooltip: 'Edit $_sectionLabel',
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
      title: Text(_isRegion ? 'Pengurus Daerah' : 'Badan Pengurus Jemaat'),
      actions: [
        if (_isRegion)
          IconButton(
            tooltip: 'Data pengurus sebelumnya',
            icon: const Icon(Icons.list_alt),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DaerahRecordsPage(
                  namaDaerah: widget.namaDaerah!,
                  type: DaerahRecordType.pengurus,
                ),
              ),
            ),
          ),
      ],
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
                  if (snapshot.hasError) {
                    if (!_isRegion) {
                      return pengurusMessage(
                        pengurusError(snapshot.error!),
                        retry: _retry,
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        pengurusMessage(
                          snapshot.error is FirebaseException &&
                                  (snapshot.error as FirebaseException).code ==
                                      'permission-denied'
                              ? 'Data Pengurus Daerah belum dapat dibaca. Administrator perlu memeriksa aturan akses Firestore untuk struktur_pengurus_daerah.'
                              : pengurusError(snapshot.error!),
                          retry: _retry,
                        ),
                        for (final group in const {
                          'Pimpinan': ['KETUA BPHD', 'WAKIL KETUA'],
                          'Sekretariat': ['SEKRETARIS 1', 'SEKRETARIS 2'],
                          'Kebendaharaan': ['BENDAHARA 1', 'BENDAHARA 2'],
                        }.entries)
                          _card(group.key, [
                            for (final role in group.value)
                              ListTile(
                                leading: pengurusAvatar(null),
                                title: const Text('Data belum dapat dimuat'),
                                subtitle: Text(role),
                              ),
                          ]),
                      ],
                    );
                  }
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  if (!snapshot.data!.exists && !_isRegion)
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
                        '${entry.value} ${pengurusText(data['${_repo!.corePrefix}_${entry.key}'])}',
                      ))
                        _person(
                          entry.value,
                          pengurusText(
                            data['${_repo!.corePrefix}_${entry.key}'],
                          ),
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
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          labelText: 'Cari pengurus atau $_sectionLabel',
                        ),
                      ),
                      const SizedBox(height: 16),
                      group('Pimpinan', {
                        'ketua': _isRegion ? 'KETUA BPHD' : 'KETUA BPJ',
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
              _dynamic(
                'Penasehat',
                _isRegion ? 'penasehat' : 'bpj_penasehat',
                _penasehatStream,
              ),
              if (_isRegion) _dynamic('MKDP', 'mkdp', _mkdpStream),
              _dynamic(
                'Badan Pemeriksa Keuangan (BPK)',
                _isRegion ? 'bpk' : 'bpj_bpk',
                _bpkStream,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _isRegion ? 'KOMISI DAERAH' : 'SEKSI & KOMISI',
                  style: const TextStyle(fontWeight: FontWeight.bold),
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
                      (a, b) => pengurusText(a.data()[_repo!.sectionNameKey])
                          .toLowerCase()
                          .compareTo(
                            pengurusText(
                              b.data()[_repo!.sectionNameKey],
                            ).toLowerCase(),
                          ),
                    );
                  final rows = <Widget>[];
                  for (final doc in docs) {
                    final data = doc.data();
                    final name = pengurusText(data[_repo!.sectionNameKey]);
                    final chair = pengurusText(
                      data['ketua_nama'] ?? data['namaPengurus'],
                    );
                    if (!_matches('$name $chair')) continue;
                    rows.add(
                      _card(
                        name.isEmpty ? _sectionLabel : name,
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
                              ? 'Belum ada data $_sectionLabel.'
                              : 'Tidak ada $_sectionLabel yang cocok.',
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
            label: Text('Tambah $_sectionLabel'),
          )
        : null,
  );
}
