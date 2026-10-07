import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'approval_service.dart';
import 'user_manager.dart';
import 'profile_service.dart';
import 'sinkronisasi_jemaat_page.dart';

class ValidasiGerejaPage extends StatefulWidget {
  final String userUid, userName, userEmail;
  const ValidasiGerejaPage({super.key, required this.userUid, required this.userName, required this.userEmail});
  @override State<ValidasiGerejaPage> createState() => _ValidasiGerejaPageState();
}
class _ValidasiGerejaPageState extends State<ValidasiGerejaPage> {
  final _code = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  bool _loading = false;
  String? _message;
  bool get _current => _auth.currentUser?.uid == widget.userUid;
  @override void dispose() { _code.dispose(); super.dispose(); }
  Future<void> _submit() async {
    if (_loading || !_current) return;
    if (_code.text.trim().isEmpty) { setState(() => _message = 'Masukkan kode undangan.'); return; }
    setState(() { _loading = true; _message = null; });
    try {
      final ref = _db.collection('users').doc(widget.userUid);
      await _db.runTransaction((tx) async {
        final account = await tx.get(ref);
        if (!_current) throw StateError('Sesi berubah.');
        if (!account.exists) tx.set(ref, {'uid': widget.userUid, 'email': widget.userEmail,
          'namaLengkap': widget.userName, 'photoUrl': _auth.currentUser?.photoURL,
          'role': 'user', 'isBlocked': false, 'churchId': '', 'churchName': '',
          'jemaatId': '', 'isPengurus': false, 'daerah': ''});
      }).timeout(const Duration(seconds: 20));
      if (!_current) throw StateError('Sesi berubah.');
      await ApprovalService().call('requestChurchMembership', {'code': _code.text.trim()});
      if (mounted && _current) setState(() => _message = 'Permohonan terkirim. Tunggu persetujuan Admin Gereja, lalu tekan Periksa persetujuan.');
    } catch (e) { if (mounted) setState(() => _message = profileError(e)); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  Future<void> _refresh() async {
    if (_loading || !_current) return;
    setState(() { _loading = true; _message = null; });
    try {
      final account = await FirebaseProfileGateway().loadAccount();
      if (!mounted || !_current) return;
      if (account.churchId.isEmpty) {
        final request = await _db.collection('profile_requests').doc('membership_${widget.userUid}')
          .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));
        if (mounted && _current) setState(() => _message = request.data()?['status'] == 'rejected'
          ? 'Permohonan ditolak. Periksa kode dan identitas dengan admin sebelum mengirim ulang.'
          : 'Gereja belum disetujui. Hubungi Admin Gereja atau periksa lagi nanti.');
        return;
      }
      // Account/church/link remain authoritative; cache failure can be retried.
      await UserManager().setUser(role: account.role, churchId: account.churchId, churchName: account.churchName,
        uId: account.uid, uNama: account.name, uFoto: account.photo,
        uKomisi: account.data['kelompok']?.toString() ?? 'Umum',
        uAdminDaerahArea: account.data['adminDaerahArea']?.toString(), uDaerah: account.data['daerah']?.toString(),
        uIsPengurus: account.data['isPengurus'] == true);
      if (!mounted || !_current) return;
      try { OneSignal.User.addTagWithKey('active_church', account.churchId); } catch (_) {}
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const SinkronisasiJemaatPage()), (_) => false);
    } catch (e) { if (mounted) setState(() => _message = profileError(e)); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  Future<void> _logout() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await FirebaseProfileGateway().logout();
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (e) { if (mounted) setState(() => _message = profileError(e)); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  @override Widget build(BuildContext context) => PopScope(canPop: false, child: Scaffold(
    appBar: AppBar(title: const Text('Pendaftaran Gereja'), leading: IconButton(onPressed: _loading ? null : _logout, icon: const Icon(Icons.arrow_back))),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      const Text('Masukkan kode undangan dari gereja Anda. Admin Gereja memeriksa identitas dan menyetujui keanggotaan.'),
      const SizedBox(height: 24),
      TextField(controller: _code, enabled: !_loading && _current, maxLength: 100,
        decoration: const InputDecoration(labelText: 'Kode undangan')),
      if (_loading) const LinearProgressIndicator(),
      if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(_message!)),
      ElevatedButton(onPressed: _loading || !_current ? null : _submit, child: const Text('Ajukan ke Admin Gereja')),
      TextButton(onPressed: _loading || !_current ? null : _refresh, child: const Text('Periksa persetujuan')),
      TextButton(onPressed: _loading ? null : _logout, child: const Text('Kembali ke login')),
    ])));
}
