import 'dart:async';
import 'package:flutter/material.dart';
import 'management_service.dart';
import 'management_support.dart';

class AddEditGerejaPage extends StatefulWidget {
  final String? gerejaId;
  final ManagementGateway? gateway;
  const AddEditGerejaPage({super.key, this.gerejaId, this.gateway});
  @override State<AddEditGerejaPage> createState() => _AddEditGerejaPageState();
}
class _AddEditGerejaPageState extends State<AddEditGerejaPage> {
  late final ManagementGateway _gateway;
  late final String _id;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _region = TextEditingController(), _address = TextEditingController();
  StreamSubscription<String?>? _auth;
  ManagementRecord? _expected;
  String? _error;
  bool _busy = false, _ready = false, _expired = false, _uncertain = false;
  int _request = 0;
  @override void initState() {
    super.initState();
    _gateway = widget.gateway ?? FirebaseManagementGateway();
    _id = widget.gerejaId ?? _gateway.newChurchId();
    final uid = _gateway.signedInUid;
    _auth = _gateway.authChanges.listen((id) {
      if (mounted && id != uid) { _request++; setState(() { _expired = true; _busy = false; _ready = false; }); }
    });
    _load();
  }
  @override void dispose() { _request++; _auth?.cancel(); _name.dispose(); _region.dispose(); _address.dispose(); super.dispose(); }
  Future<void> _load() async {
    if (!mounted || _expired || _busy) return;
    final request = ++_request;
    setState(() { _busy = true; _ready = false; _error = null; });
    try {
      final access = await _gateway.access();
      if (!access.superAdmin) throw StateError('Hanya Superadmin yang dapat mengelola gereja.');
      ManagementRecord? church;
      if (widget.gerejaId != null || _uncertain) {
        try { church = await _gateway.loadChurch(_id); }
        on StateError catch (error) {
          // A new church may not have committed. Reuse its ID and invitation code on retry.
          if (widget.gerejaId != null || error.message != 'Gereja tidak ditemukan.') rethrow;
        }
      }
      if (!mounted || request != _request) return;
      if (church != null) {
        _expected = church;
        _name.text = managementText(church.data['namaGereja'], managementText(church.data['nama'], managementText(church.data['churchName'])));
        _region.text = managementText(church.data['daerah']);
        _address.text = managementText(church.data['alamat']);
      }
      setState(() { _ready = true; _uncertain = false; });
    } catch (error) { if (mounted && request == _request) setState(() => _error = managementError(error)); }
    finally { if (mounted && request == _request) setState(() => _busy = false); }
  }
  Future<void> _save() async {
    if (_busy || !_ready || _expired || _uncertain || !(_form.currentState?.validate() ?? false)) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _gateway.saveChurch(_id, {'namaGereja': _name.text.trim(), 'daerah': _region.text.trim(), 'alamat': _address.text.trim()}, expected: _expected);
      if (!mounted || _expired) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data gereja berhasil disimpan.')));
      setState(() => _busy = false);
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted && !_expired) setState(() {
        _error = managementError(error);
        // An uncertain commit must be checked before another attempt.
        if (managementUncertain(error)) { _uncertain = true; _ready = false; }
        if (error is StateError) _ready = false;
      });
    } finally { if (mounted && !_expired) setState(() => _busy = false); }
  }
  String? _required(String? value) => managementText(value).isEmpty ? 'Kolom ini wajib diisi.' : null;
  @override Widget build(BuildContext context) => PopScope(canPop: !_busy, child: Scaffold(
    appBar: AppBar(title: Text(widget.gerejaId == null ? 'Tambah Gereja' : 'Edit Gereja')),
    body: _expired ? const Center(child: Text('Sesi berubah. Silakan masuk ulang.')) : Form(key: _form,
      child: ListView(padding: const EdgeInsets.all(20), children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[Text(_error!, style: const TextStyle(color: Colors.red)),
          TextButton(onPressed: _busy ? null : _load, child: const Text('Muat ulang data'))],
        const SizedBox(height: 20),
        TextFormField(controller: _name, enabled: _ready && !_busy, decoration: const InputDecoration(labelText: 'Nama Gereja'), validator: _required),
        const SizedBox(height: 20),
        TextFormField(controller: _region, enabled: _ready && !_busy, decoration: const InputDecoration(labelText: 'Nama Daerah / Wilayah'), validator: _required),
        const SizedBox(height: 20),
        TextFormField(controller: _address, enabled: _ready && !_busy, maxLines: 3, decoration: const InputDecoration(labelText: 'Alamat Lengkap')),
        const SizedBox(height: 24),
        if (_expected != null) const Text('Kode undangan lama tetap dipertahankan.'),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: _ready && !_busy && !_uncertain ? _save : null, child: const Text('SIMPAN GEREJA')),
      ]))));
}
