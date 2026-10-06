import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'profile_service.dart';
import 'profile_support.dart';
import 'main.dart';

class SinkronisasiJemaatPage extends StatefulWidget {
  final bool returnToProfile;
  final ProfileGateway? gateway;
  const SinkronisasiJemaatPage({super.key, this.returnToProfile = false, this.gateway});
  @override State<SinkronisasiJemaatPage> createState() => _SinkronisasiJemaatPageState();
}
class _SinkronisasiJemaatPageState extends State<SinkronisasiJemaatPage> {
  late final ProfileGateway _gateway;
  late final String? _sessionUid;
  StreamSubscription<String?>? _authSubscription;
  final _phone = TextEditingController(), _year = TextEditingController();
  ProfileCandidate? _candidate;
  bool _loading = false, _uncertain = false;
  String? _error;
  int _request = 0;
  bool get _sameSession => _sessionUid != null && _gateway.signedInUid == _sessionUid;
  @override void initState() {
    super.initState();
    _gateway = widget.gateway ?? FirebaseProfileGateway();
    _sessionUid = _gateway.signedInUid;
    _authSubscription = _gateway.authChanges.listen((uid) {
      if (!mounted || uid == _sessionUid) return;
      _request++;
      setState(() { _candidate = null; _year.clear(); _phone.clear(); _loading = false; _error = 'Sesi akun berubah. Silakan masuk ulang.'; });
    });
  }
  @override void dispose() { _request++; _authSubscription?.cancel(); _phone.dispose(); _year.dispose(); super.dispose(); }
  Future<void> _search() async {
    if (_loading || !_sameSession || _uncertain) return;
    final phone = _phone.text.trim();
    if (profilePhone(phone) == null) { setState(() => _error = 'Masukkan nomor HP/WhatsApp yang valid.'); return; }
    final request = ++_request;
    setState(() { _loading = true; _candidate = null; _year.clear(); _error = null; });
    FocusScope.of(context).unfocus();
    try {
      final candidate = await _gateway.search(phone);
      if (!mounted || request != _request || !_sameSession || candidate.uid != _sessionUid) return;
      setState(() => _candidate = candidate);
    } catch (e) {
      if (mounted && request == _request && _sameSession) setState(() => _error = profileError(e));
    } finally { if (mounted && request == _request) setState(() => _loading = false); }
  }
  Future<void> _verify() async {
    final candidate = _candidate;
    if (_loading || _uncertain || !_sameSession || candidate == null) return;
    final year = _year.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(year)) { setState(() => _error = 'Tahun lahir harus empat digit angka.'); return; }
    final request = ++_request;
    setState(() { _loading = true; _error = null; });
    FocusScope.of(context).unfocus();
    try {
      final cacheSaved = await _gateway.link(candidate, year);
      if (!mounted || request != _request || !_sameSession) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(cacheSaved
        ? 'Data jemaat berhasil ditautkan.' : 'Data berhasil ditautkan. Cache lokal belum diperbarui; profil akan dimuat ulang.')));
      _finish(true);
    } catch (e) {
      if (mounted && request == _request && _sameSession) setState(() { _error = profileError(e); _uncertain = e is TimeoutException; });
    } finally { if (mounted && request == _request) setState(() => _loading = false); }
  }
  void _finish(bool linked) {
    if (widget.returnToProfile) { Navigator.pop(context, linked); }
    else { Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainActivity()), (_) => false); }
  }
  @override Widget build(BuildContext context) => PopScope(canPop: !_loading, child: Scaffold(
    backgroundColor: Colors.white, appBar: AppBar(title: const Text('Hubungkan Data Jemaat'), backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
      leading: _loading ? const SizedBox.shrink() : null),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      if (_loading) const LinearProgressIndicator(),
      const Icon(Icons.link, size: 64, color: Colors.indigo),
      const SizedBox(height: 16), const Text('Tautan memakai gereja asal akun, bukan gereja yang sedang dipantau.', textAlign: TextAlign.center),
      if (!_sameSession) const Padding(padding: EdgeInsets.all(16), child: Text('Sesi login berakhir atau akun berubah. Silakan masuk ulang.')),
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(_error!, style: const TextStyle(color: Colors.red))),
      if (_uncertain) const Text('Hasil penautan belum pasti. Pengiriman ulang dinonaktifkan. Kembali dan periksa profil terbaru.'),
      if (_candidate == null) ...[
        const SizedBox(height: 24), TextField(controller: _phone, enabled: !_loading && !_uncertain && _sameSession,
          keyboardType: TextInputType.phone, maxLength: 30, decoration: const InputDecoration(labelText: 'Nomor HP/WhatsApp', hintText: '0812… atau +62812…')),
        ElevatedButton(onPressed: _loading || _uncertain || !_sameSession ? null : _search, child: const Text('CARI DATA SAYA')),
      ] else ...[
        const SizedBox(height: 24), Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          const Text('Data ditemukan', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(profileMaskedName(_candidate!.data['namaLengkap'])),
          const Text('Nama ditampilkan sebagian sebelum verifikasi.'),
        ]))),
        TextField(controller: _year, enabled: !_loading && !_uncertain && _sameSession, keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 4, decoration: const InputDecoration(labelText: 'Tahun lahir (empat digit)')),
        ElevatedButton.icon(onPressed: _loading || _uncertain || !_sameSession ? null : _verify, icon: const Icon(Icons.verified_user), label: const Text('VERIFIKASI & HUBUNGKAN')),
        TextButton(onPressed: _loading || _uncertain ? null : () => setState(() { _request++; _candidate = null; _phone.clear(); _year.clear(); _error = null; }), child: const Text('Bukan data saya, cari ulang')),
      ],
      const SizedBox(height: 24), const Text('Jika nomor dipakai bersama, tanggal lahir belum valid, atau tautan salah, hubungi Admin Gereja. Tautan lama tidak dipindah otomatis.', textAlign: TextAlign.center),
      const SizedBox(height: 24), TextButton(onPressed: _loading ? null : () {
        if (!_sameSession) { Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false); }
        else { _finish(false); }
      }, child: Text(!_sameSession ? 'Masuk ulang' : widget.returnToProfile ? 'Kembali ke Profil' : 'Lewati sementara (Masuk ke Beranda)')),
    ]),
  ));
}
