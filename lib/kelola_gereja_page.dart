import 'region_names.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'add_edit_gereja_page.dart';
import 'management_service.dart';
import 'management_support.dart';
import 'user_manager.dart';

class KelolaGerejaPage extends StatefulWidget {
  final ManagementGateway? gateway;
  final String? area, areaLabel;
  final bool initialArchived;
  final String initialSearch;
  const KelolaGerejaPage({
    super.key,
    this.gateway,
    this.area,
    this.areaLabel,
    this.initialArchived = false,
    this.initialSearch = '',
  });
  @override
  State<KelolaGerejaPage> createState() => _KelolaGerejaPageState();
}

class _KelolaGerejaPageState extends State<KelolaGerejaPage> {
  late final ManagementGateway _gateway;
  late Stream<List<ManagementRecord>> _stream;
  StreamSubscription<String?>? _auth;
  bool _busy = false, _expired = false, _showArchived = false;
  String? _error;
  late final TextEditingController _search;
  @override
  void initState() {
    super.initState();
    _showArchived = widget.initialArchived;
    _search = TextEditingController(text: widget.initialSearch);
    _gateway = widget.gateway ?? FirebaseManagementGateway();
    _stream = _gateway.churches();
    final uid = _gateway.signedInUid;
    _auth = _gateway.authChanges.listen((id) {
      if (mounted && id != uid)
        setState(() {
          _expired = true;
          _busy = false;
        });
    });
  }

  @override
  void dispose() {
    _auth?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _openRegion(RegionNameGroup region) async {
    if (_busy || _expired) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => KelolaGerejaPage(
          gateway: _gateway,
          area: region.name,
          areaLabel: region.displayName,
          initialArchived: _showArchived,
          initialSearch:
              _searchText(region.name).contains(_searchText(_search.text)) ||
                  _searchText(
                    region.displayName,
                  ).contains(_searchText(_search.text))
              ? ''
              : _search.text,
        ),
      ),
    );
    if (!mounted || _expired) return;
    if (changed == true) {
      Navigator.pop(context, true);
    } else {
      setState(() => _stream = _gateway.churches());
    }
  }

  String _searchText(Object? value) => cleanRegionName(value).toLowerCase();

  Future<void> _enter(ManagementRecord church) async {
    if (_busy || _expired) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _gateway.enterChurch(church);
      if (!mounted || _expired) return;
      setState(() => _busy = false);
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted && !_expired) setState(() => _error = managementError(error));
    } finally {
      if (mounted && !_expired) setState(() => _busy = false);
    }
  }

  Future<void> _edit([String? id]) async {
    if (_busy || _expired) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditGerejaPage(gerejaId: id, gateway: _gateway),
      ),
    );
    if (mounted && !_expired) setState(() => _stream = _gateway.churches());
  }

  Future<void> _delete(ManagementRecord church, {bool restore = false}) async {
    if (_busy || _expired) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(restore ? 'Pulihkan Gereja?' : 'Hapus Gereja?'),
        content: Text(
          restore
              ? 'Pulihkan ${managementChurchName(church.data)} ke daftar aktif?'
              : 'Hapus ${managementChurchName(church.data)} dari daftar aktif? Gereja yang masih memiliki akun, jemaat, atau riwayat tidak dapat dihapus. Entri disimpan dalam arsip dan kode undangannya dinonaktifkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(restore ? 'Pulihkan' : 'Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _expired || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (restore) {
        await _gateway.restoreChurch(church);
      } else {
        await _gateway.deleteChurch(church);
      }
      if (mounted && !_expired)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              restore
                  ? 'Gereja dipulihkan.'
                  : 'Gereja dihapus dari daftar aktif.',
            ),
          ),
        );
    } catch (error) {
      if (mounted && !_expired) setState(() => _error = managementError(error));
    } finally {
      if (mounted && !_expired) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String code) async {
    try {
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted && !_expired)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Kode undangan disalin.')));
    } catch (_) {
      if (mounted && !_expired)
        setState(() => _error = 'Kode belum dapat disalin.');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.area == null
              ? (_showArchived ? 'Arsip Gereja per Daerah' : 'Kelola Gereja')
              : '${_showArchived ? 'Arsip' : 'Gereja'} • ${widget.areaLabel ?? cleanRegionName(widget.area)}',
        ),
        actions: [
          IconButton(
            tooltip: _showArchived ? 'Daftar aktif' : 'Arsip gereja',
            onPressed: _busy || _expired
                ? null
                : () => setState(() => _showArchived = !_showArchived),
            icon: Icon(_showArchived ? Icons.church : Icons.archive_outlined),
          ),
        ],
      ),
      floatingActionButton: _expired
          ? null
          : FloatingActionButton(
              onPressed: _busy ? null : () => _edit(),
              tooltip: 'Tambah Gereja Baru',
              child: const Icon(Icons.add),
            ),
      body: _expired
          ? const Center(child: Text('Sesi berubah. Silakan masuk ulang.'))
          : Column(
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _search,
                    enabled: !_busy,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: widget.area == null
                          ? 'Cari gereja atau daerah'
                          : 'Cari gereja di daerah ini',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Hapus pencarian',
                              onPressed: _busy
                                  ? null
                                  : () => setState(_search.clear),
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                ),
                if (widget.area == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      'Pilih daerah untuk melihat dan mengelola gereja.',
                    ),
                  ),
                Expanded(
                  child: StreamBuilder<List<ManagementRecord>>(
                    stream: _stream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError)
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  managementError(snapshot.error!),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(
                                        () => _stream = _gateway.churches(),
                                      ),
                                child: const Text('Coba lagi'),
                              ),
                            ],
                          ),
                        );
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final churches =
                          snapshot.data!
                              .where(
                                (church) =>
                                    (church.data['isArchived'] == true) ==
                                    _showArchived,
                              )
                              .where(
                                (church) =>
                                    widget.area == null ||
                                    regionNameKey(church.data['daerah']) ==
                                        regionNameKey(widget.area),
                              )
                              .where((church) {
                                final query = _searchText(_search.text);
                                return query.isEmpty ||
                                    _searchText(
                                      managementChurchName(church.data),
                                    ).contains(query) ||
                                    (widget.area == null &&
                                        (_searchText(
                                              church.data['daerah'],
                                            ).contains(query) ||
                                            _searchText(
                                              church.data['namaDaerah'],
                                            ).contains(query)));
                              })
                              .toList()
                            ..sort(
                              (a, b) => managementChurchName(
                                a.data,
                              ).compareTo(managementChurchName(b.data)),
                            );
                      if (churches.isEmpty)
                        return Center(
                          child: Text(
                            _search.text.trim().isNotEmpty
                                ? 'Gereja atau daerah tidak ditemukan.'
                                : _showArchived
                                ? 'Arsip gereja kosong.'
                                : 'Belum ada data gereja. Tekan + untuk menambah.',
                          ),
                        );
                      if (widget.area == null) {
                        final regions = groupChurchRegions(
                          churches.map(
                            (church) => {...church.data, 'isArchived': false},
                          ),
                        );
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          itemCount: regions.length,
                          itemBuilder: (context, index) {
                            final region = regions[index];
                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.map_outlined),
                                ),
                                title: Text(
                                  region.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${region.count} Gereja${_search.text.trim().isEmpty ? '' : ' ditemukan'}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _busy ? null : () => _openRegion(region),
                              ),
                            );
                          },
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: churches.length,
                        itemBuilder: (context, index) {
                          final church = churches[index], data = church.data;
                          final name = managementChurchName(data),
                              code = managementText(data['kodeUndangan']);
                          final active =
                              UserManager().getChurchIdForCurrentView() ==
                              church.id;
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.church),
                                    title: Text(name),
                                    subtitle: Text(
                                      'Daerah: ${managementText(data['daerah'], 'Belum diatur')}\n${managementText(data['alamat'], 'Alamat belum diisi')}',
                                    ),
                                    trailing: IconButton(
                                      onPressed: _busy || _showArchived
                                          ? null
                                          : () => _edit(church.id),
                                      icon: const Icon(Icons.edit),
                                      tooltip: 'Edit Info Gereja',
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 12,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        code.isEmpty
                                            ? 'Kode belum tersedia'
                                            : code,
                                      ),
                                      if (code.isNotEmpty)
                                        IconButton(
                                          onPressed: _busy
                                              ? null
                                              : () => _copy(code),
                                          icon: const Icon(Icons.copy),
                                          tooltip: 'Salin kode',
                                        ),
                                      ElevatedButton(
                                        onPressed:
                                            _busy || active || _showArchived
                                            ? null
                                            : () => _enter(church),
                                        child: Text(
                                          active
                                              ? 'Sedang Aktif'
                                              : 'Kelola Data',
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed:
                                            _busy || (active && !_showArchived)
                                            ? null
                                            : () => _delete(
                                                church,
                                                restore: _showArchived,
                                              ),
                                        icon: Icon(
                                          _showArchived
                                              ? Icons.restore
                                              : Icons.delete_outline,
                                        ),
                                        label: Text(
                                          _showArchived
                                              ? 'Pulihkan'
                                              : 'Hapus Gereja',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
  );
}
