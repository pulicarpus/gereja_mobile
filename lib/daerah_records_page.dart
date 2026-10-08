import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_safety.dart';
import 'pengurus_support.dart';
import 'pengurus_widgets.dart';
import 'user_manager.dart';

enum DaerahRecordType { pengurus, inventaris }

class DaerahRecordsPage extends StatefulWidget {
  final String namaDaerah;
  final DaerahRecordType type;
  const DaerahRecordsPage({
    super.key,
    required this.namaDaerah,
    required this.type,
  });

  @override
  State<DaerahRecordsPage> createState() => _DaerahRecordsPageState();
}

class _DaerahRecordsPageState extends State<DaerahRecordsPage> {
  String _search = '';
  late final CollectionReference<Map<String, dynamic>> _collection;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  bool get _inventory => widget.type == DaerahRecordType.inventaris;
  String get _title => _inventory ? 'Inventaris Daerah' : 'Pengurus Daerah';
  bool get _canEdit {
    final user = UserManager();
    return user.isSuperAdmin() ||
        (user.isAdminDaerah() &&
            user.adminDaerahArea?.trim() == widget.namaDaerah.trim());
  }

  Map<String, String> get _fields => _inventory
      ? const {
          'nama': 'Nama barang',
          'kode': 'Kode inventaris',
          'jumlah': 'Jumlah',
          'satuan': 'Satuan',
          'kondisi': 'Kondisi',
          'lokasi': 'Lokasi penyimpanan',
          'penanggungJawab': 'Penanggung jawab',
          'keterangan': 'Keterangan',
        }
      : const {
          'nama': 'Nama lengkap',
          'jabatan': 'Jabatan',
          'gereja': 'Asal gereja',
          'telepon': 'Nomor WhatsApp',
          'periode': 'Periode pelayanan',
          'keterangan': 'Keterangan',
        };

  @override
  void initState() {
    super.initState();
    _collection = FirebaseFirestore.instance.collection(
      _inventory ? 'inventaris_daerah' : 'pengurus_daerah',
    );
    _connect();
  }

  void _connect() {
    _stream = _collection
        .where('daerah', isEqualTo: widget.namaDaerah)
        .snapshots();
  }

  Future<void> _edit([DocumentSnapshot<Map<String, dynamic>>? record]) async {
    if (!_canEdit) return;
    final ref = record?.reference ?? _collection.doc();
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DaerahRecordDialog(
        title:
            '${record == null ? 'Tambah' : 'Ubah'} ${_inventory ? 'inventaris' : 'pengurus'}',
        fields: _fields,
        initial:
            record?.data() ??
            (_inventory
                ? {'jumlah': 1, 'satuan': 'unit', 'kondisi': 'Baik'}
                : {}),
        inventory: _inventory,
        onSave: (data) async {
          await saveRegionChanges(
            widget.namaDaerah,
            {
              ref: {
                ...data,
                'daerah': widget.namaDaerah,
                if (record == null) 'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              },
            },
            createOnly: record == null,
            requireExisting: record != null,
            allowPastors: false,
          );
        },
      ),
    );
  }

  Future<void> _detail(DocumentSnapshot<Map<String, dynamic>> record) async {
    final data = record.data() ?? {};
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(legacyText(data['nama'])),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final field in _fields.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          field.value,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          legacyText(data[field.key]).isEmpty
                              ? '—'
                              : legacyText(data[field.key]),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (_canEdit)
            TextButton(
              onPressed: () => Navigator.pop(context, 'delete'),
              child: const Text('Hapus'),
            ),
          if (_canEdit)
            TextButton(
              onPressed: () => Navigator.pop(context, 'edit'),
              child: const Text('Ubah'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'edit') await _edit(record);
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hapus data?'),
          content: Text('Hapus ${legacyText(data['nama'])} dari $_title?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || !_canEdit) return;
      try {
        await saveRegionChanges(widget.namaDaerah, {
          record.reference: null,
        }, allowPastors: false);
      } catch (error) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(pengurusError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FA),
    appBar: AppBar(
      title: Text(_title),
      backgroundColor: Colors.indigo.shade900,
      foregroundColor: Colors.white,
    ),
    floatingActionButton: _canEdit
        ? FloatingActionButton.extended(
            onPressed: _edit,
            icon: const Icon(Icons.add),
            label: const Text('Tambah'),
          )
        : null,
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.namaDaerah,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (value) =>
                        setState(() => _search = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: _inventory
                          ? 'Cari barang, kode, atau lokasi'
                          : 'Cari nama atau jabatan',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _stream,
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return Center(
                      child: pengurusMessage(
                        pengurusError(snapshot.error!),
                        retry: () => setState(_connect),
                      ),
                    );
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final records =
                      snapshot.data!.docs
                          .where(
                            (record) => _fields.keys.any(
                              (key) => legacyText(
                                record.data()[key],
                              ).toLowerCase().contains(_search),
                            ),
                          )
                          .toList()
                        ..sort(
                          (a, b) => legacyText(a.data()['nama'])
                              .toLowerCase()
                              .compareTo(
                                legacyText(b.data()['nama']).toLowerCase(),
                              ),
                        );
                  if (records.isEmpty)
                    return Center(
                      child: Text(
                        _search.isNotEmpty
                            ? 'Data tidak ditemukan.'
                            : _inventory
                            ? 'Belum ada inventaris daerah.'
                            : 'Belum ada data pengurus daerah.',
                      ),
                    );
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    itemCount: records.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final record = records[index];
                      final data = record.data();
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: Colors.indigo.shade50,
                            child: Icon(
                              _inventory
                                  ? Icons.inventory_2_outlined
                                  : Icons.person_outline,
                              color: Colors.indigo,
                            ),
                          ),
                          title: Text(
                            legacyText(data['nama']),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            _inventory
                                ? '${legacyText(data['jumlah'])} ${legacyText(data['satuan'])} • ${legacyText(data['lokasi'])}'
                                : '${legacyText(data['jabatan'])}${legacyText(data['gereja']).isEmpty ? '' : ' • ${legacyText(data['gereja'])}'}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _detail(record),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DaerahRecordDialog extends StatefulWidget {
  final String title;
  final Map<String, String> fields;
  final Map<String, dynamic> initial;
  final bool inventory;
  final Future<void> Function(Map<String, dynamic>) onSave;
  const _DaerahRecordDialog({
    required this.title,
    required this.fields,
    required this.initial,
    required this.inventory,
    required this.onSave,
  });
  @override
  State<_DaerahRecordDialog> createState() => _DaerahRecordDialogState();
}

class _DaerahRecordDialogState extends State<_DaerahRecordDialog> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final key in widget.fields.keys)
        key: TextEditingController(text: legacyText(widget.initial[key])),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{
        for (final entry in _controllers.entries)
          entry.key: entry.value.text.trim(),
      };
      if (widget.inventory) data['jumlah'] = int.parse(data['jumlah']);
      await widget.onSave(data);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = pengurusError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in widget.fields.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: TextFormField(
                      controller: _controllers[field.key],
                      enabled: !_saving,
                      maxLength: field.key == 'keterangan' ? 1500 : 150,
                      maxLines: field.key == 'keterangan' ? 3 : 1,
                      keyboardType: field.key == 'jumlah'
                          ? TextInputType.number
                          : field.key == 'telepon'
                          ? TextInputType.phone
                          : TextInputType.text,
                      decoration: InputDecoration(
                        labelText: field.value,
                        counterText: '',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (raw) {
                        final value = raw?.trim() ?? '';
                        if ((field.key == 'nama' ||
                                field.key == 'jabatan' ||
                                field.key == 'satuan') &&
                            value.isEmpty)
                          return 'Wajib diisi.';
                        if (field.key == 'jumlah' &&
                            ((int.tryParse(value) ?? 0) <= 0))
                          return 'Isi jumlah bulat lebih dari nol.';
                        if (field.key == 'telepon' &&
                            value.isNotEmpty &&
                            pengurusWa(value) == null)
                          return 'Nomor WhatsApp tidak valid.';
                        return null;
                      },
                    ),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
        ),
      ],
    ),
  );
}
