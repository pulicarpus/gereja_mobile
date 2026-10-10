import 'dart:async';
import 'package:flutter/material.dart';
import 'kategorial_config.dart';
import 'management_service.dart';
import 'management_support.dart';

class DetailPenggunaPage extends StatefulWidget {
  final String userId;
  final ManagementGateway? gateway;
  const DetailPenggunaPage({super.key, required this.userId, this.gateway});
  @override
  State<DetailPenggunaPage> createState() => _DetailPenggunaPageState();
}

class _DetailPenggunaPageState extends State<DetailPenggunaPage> {
  late final ManagementGateway _gateway;
  StreamSubscription<String?>? _auth;
  ManagementRecord? _user;
  ManagementAccess? _access;
  String? _error;
  bool _busy = false, _expired = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? FirebaseManagementGateway();
    final uid = _gateway.signedInUid;
    _auth = _gateway.authChanges.listen((id) {
      if (mounted && id != uid) {
        _request++;
        setState(() {
          _expired = true;
          _busy = false;
          _user = null;
        });
      }
    });
    _load();
  }

  @override
  void dispose() {
    _request++;
    _auth?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted || _expired) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
      _user = null;
    });
    try {
      final access = await _gateway.access();
      final user = await _gateway.loadUser(widget.userId);
      if (mounted && request == _request)
        setState(() {
          _access = access;
          _user = user;
        });
    } catch (error) {
      if (mounted && request == _request)
        setState(() => _error = managementError(error));
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _change(String field, dynamic value) async {
    if (_busy || _expired || _user == null) return;
    final expected = _user!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi perubahan'),
        content: Text(
          field == 'churchId'
              ? '${value is ChurchTransferChoice && value.wholeFamily ? 'Pindahkan seluruh keluarga' : 'Pindahkan satu orang'} ke gereja yang dipilih? Biodata dan foto ikut pindah, akun tetap tertaut. Hak admin gereja/daerah dan pengurus lokal akan dicabut untuk akun yang ikut pindah. Untuk satu orang, hubungan keluarga di tujuan menjadi keluarga sendiri. Kepala keluarga yang masih memiliki anggota harus dipindahkan bersama keluarganya atau diatur ulang dahulu.'
              : field == 'kelompok'
              ? 'Ubah kategorial ke $value? Status pengurus lokal akan di-reset.'
              : 'Simpan perubahan ${field == 'role'
                    ? 'hak akses'
                    : field == 'isPengurus'
                    ? 'pengurus lokal'
                    : 'jabatan daerah'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted || _expired || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var saved = false;
    try {
      await _gateway.changeUser(expected, field, value);
      saved = true;
      if (field == 'churchId' && mounted && !_expired) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Data jemaat dan akun dipindahkan. Pengguna cukup masuk ulang; tautan jemaat tetap terhubung.',
            ),
          ),
        );
        Navigator.pop(context);
        return;
      }
      if (!mounted || _expired) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perubahan berhasil disimpan.')),
      );
    } catch (error) {
      if (mounted && !_expired)
        setState(() {
          _error = managementError(error);
          _user = null;
        });
    } finally {
      if (mounted && !_expired) setState(() => _busy = false);
    }
    if (saved && mounted && !_expired) await _load();
  }

  Future<void> _choose(String field) async {
    if (_busy || _expired || _user == null) return;
    List<MapEntry<String, String>> choices;
    if (field == 'kelompok') {
      choices = KategorialConfig.pilihanJemaat
          .map((v) => MapEntry(v, v))
          .toList();
    } else {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        final churches = await _gateway.churchChoices();
        choices = field == 'churchId'
            ? churches
                  .where((c) => c.id != managementText(_user?.data['churchId']))
                  .map((c) => MapEntry(c.id, managementChurchName(c.data)))
                  .toList()
            : (churches
                      .map((c) => managementText(c.data['daerah']))
                      .where((v) => v.isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort())
                  .map((v) => MapEntry(v, v))
                  .toList();
        if (field == 'adminDaerahArea' &&
            managementText(_user?.data['adminDaerahArea']).isNotEmpty) {
          choices.insert(0, const MapEntry('', 'Cabut Jabatan Daerah'));
        }
      } catch (error) {
        if (mounted && !_expired)
          setState(() => _error = managementError(error));
        return;
      } finally {
        if (mounted && !_expired) setState(() => _busy = false);
      }
    }
    if (!mounted || _expired) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                field == 'churchId'
                    ? 'Pilih Gereja'
                    : field == 'kelompok'
                    ? 'Pilih Kategorial'
                    : 'Atur Jabatan Daerah',
              ),
            ),
            Expanded(
              child: choices.isEmpty
                  ? const Center(child: Text('Belum ada pilihan tersedia.'))
                  : ListView(
                      children: choices
                          .map(
                            (entry) => ListTile(
                              title: Text(entry.value),
                              onTap: () => Navigator.pop(context, entry.key),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted || _expired) return;
    if (field == 'churchId') {
      final family = await showDialog<bool>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Siapa yang dipindahkan?'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Pindahkan satu orang'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Pindahkan satu keluarga'),
            ),
          ],
        ),
      );
      if (family != null && mounted && !_expired) {
        await _change(
          field,
          ChurchTransferChoice(selected, wholeFamily: family),
        );
      }
    } else {
      await _change(field, selected);
    }
  }

  Widget _action(String title, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: OutlinedButton(
      onPressed: _busy ? null : onTap,
      child: Text(title, textAlign: TextAlign.center),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final user = _user, access = _access;
    final data = user?.data ?? <String, dynamic>{};
    final name = managementText(data['namaLengkap'], 'Tanpa Nama');
    final role = managementText(data['role'], 'user');
    final canManage = access?.canManage(data) == true;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Detail Pengguna'),
          actions: [
            IconButton(
              onPressed: _busy || _expired ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Muat ulang',
            ),
          ],
        ),
        body: _expired
            ? const Center(child: Text('Sesi berubah. Silakan masuk ulang.'))
            : _busy
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Muat ulang data'),
                      ),
                    ],
                    if (user != null) ...[
                      Center(
                        child: CircleAvatar(
                          radius: 36,
                          child: Text(name.characters.first.toUpperCase()),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        managementText(data['email'], 'Tidak ada email'),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Gereja: ${managementText(data['_churchDisplayName'], managementText(data['churchName'], managementText(data['churchId'], 'Belum diatur')))}',
                      ),
                      Text(
                        'Kategorial: ${managementText(data['kelompok'], 'Belum diatur')}',
                      ),
                      Text('Hak akses: ${role.toUpperCase()}'),
                      Text(
                        'Pengurus lokal: ${data['isPengurus'] == true ? 'Ya' : 'Tidak'}',
                      ),
                      if (managementText(data['adminDaerahArea']).isNotEmpty)
                        Text(
                          'Pengurus Daerah: ${managementText(data['adminDaerahArea'])}',
                        ),
                      if (data['isBlocked'] == true)
                        const Text('Akun dinonaktifkan.'),
                      const SizedBox(height: 20),
                      if (canManage) ...[
                        _action('Atur Kategorial', () => _choose('kelompok')),
                        if (role == 'user' &&
                            KategorialConfig.isPelayanan(data['kelompok']))
                          _action(
                            data['isPengurus'] == true
                                ? 'Cabut Pengurus Lokal'
                                : 'Jadikan Pengurus Lokal',
                            () => _change(
                              'isPengurus',
                              data['isPengurus'] != true,
                            ),
                          ),
                        if (user.id != access!.uid &&
                            (role == 'user' ||
                                role == 'admin' ||
                                role == 'gembala'))
                          _action(
                            role == 'admin' || role == 'gembala'
                                ? 'Turunkan ke Jemaat Biasa'
                                : 'Jadikan Admin Gereja',
                            () => _change(
                              'role',
                              role == 'user' ? 'admin' : 'user',
                            ),
                          ),
                        if (user.id != access.uid &&
                            (role == 'user' ||
                                (access.superAdmin && role == 'admin')))
                          _action(
                            'Jadikan Gembala Sidang',
                            () => _change('role', 'gembala'),
                          ),
                        if (role == 'user' &&
                            managementText(data['jemaatId']).isEmpty)
                          const Text(
                            'Untuk menjadi gembala, hubungkan Data Jemaat melalui Profil Saya terlebih dahulu.',
                          ),
                        if (access.superAdmin) ...[
                          if (user.id != access.uid)
                            _action(
                              'Atur / Pindah Gereja',
                              () => _choose('churchId'),
                            ),
                          _action(
                            'Atur Jabatan Daerah',
                            () => _choose('adminDaerahArea'),
                          ),
                        ],
                      ] else
                        const Text(
                          'Hak akses akun ini dilindungi atau berada di luar kewenangan Anda.',
                        ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
