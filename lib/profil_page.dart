import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'profile_service.dart';
import 'profile_support.dart';
import 'sinkronisasi_jemaat_page.dart';

class ProfilPage extends StatefulWidget {
  final ProfileGateway? gateway;
  const ProfilPage({super.key, this.gateway});
  @override State<ProfilPage> createState() => _ProfilPageState();
}
class _ProfilPageState extends State<ProfilPage> {
  late final ProfileGateway _gateway;
  late final String? _sessionUid;
  StreamSubscription<String?>? _authSubscription;
  final _name = TextEditingController();
  ProfileAccount? _account;
  ProfileBook _book = const ProfileBook(null);
  File? _image;
  bool _loading = false, _saving = false, _picking = false, _leaving = false, _navigating = false;
  bool _useBookPhoto = false, _uncertainSave = false, _confirmingExit = false;
  String? _error, _bookError;
  int _request = 0;
  bool get _sameSession => _sessionUid != null && _gateway.signedInUid == _sessionUid;
  bool get _busy => _saving || _picking || _leaving || _navigating || _confirmingExit;
  bool get _dirty => _account != null && (_name.text.trim() != _account!.name || _image != null || _useBookPhoto);
  @override void initState() {
    super.initState();
    _gateway = widget.gateway ?? FirebaseProfileGateway();
    _sessionUid = _gateway.signedInUid;
    _account = _gateway.cachedAccount;
    _name.text = _account?.name ?? '';
    _authSubscription = _gateway.authChanges.listen((uid) {
      if (!mounted || uid == _sessionUid) return;
      _request++;
      setState(() { _account = null; _book = const ProfileBook(null); _name.clear(); _image = null; _loading = false; _saving = false; _picking = false; });
    });
    _reload();
  }
  @override void dispose() { _request++; _authSubscription?.cancel(); _name.dispose(); super.dispose(); }
  Future<void> _reload() async {
    if (!mounted || !_sameSession || _busy) return;
    final request = ++_request;
    setState(() { _loading = true; _error = null; _bookError = null; _book = const ProfileBook(null); });
    try {
      final account = await _gateway.loadAccount();
      if (!mounted || request != _request || !_sameSession || account.uid != _sessionUid) return;
      final preserveName = _account != null && _name.text.trim() != _account!.name;
      setState(() { _account = account; if (!preserveName) _name.text = account.name; });
      if (account.linked) {
        try {
          final book = await _gateway.loadBook(account);
          if (mounted && request == _request && _sameSession) setState(() => _book = book);
        } catch (e) {
          if (mounted && request == _request && _sameSession) setState(() => _bookError = profileError(e));
        }
      }
    } catch (e) {
      if (mounted && request == _request && _sameSession) setState(() => _error = profileError(e));
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }
  Future<void> _pick() async {
    if (_busy || _loading || _uncertainSave || !_sameSession) return;
    setState(() { _picking = true; _error = null; });
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1600, maxHeight: 1600);
      if (mounted && _sameSession && picked != null) setState(() { _image = File(picked.path); _useBookPhoto = false; });
    } catch (_) {
      if (mounted && _sameSession) setState(() => _error = 'Foto tidak dapat dipilih. Silakan coba lagi.');
    } finally { if (mounted) setState(() => _picking = false); }
  }
  Future<void> _save() async {
    if (_busy || _loading || _uncertainSave || !_sameSession || _account == null) return;
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 120) { setState(() => _error = 'Nama wajib diisi, maksimal 120 karakter.'); return; }
    final account = _account!, image = _image, useBook = _useBookPhoto;
    setState(() { _saving = true; _error = null; });
    try {
      final result = await _gateway.save(account, name, photo: image, useBookPhoto: useBook);
      if (!mounted || !_sameSession) return;
      setState(() { _account = result.account; _name.text = result.account.name; _image = null; _useBookPhoto = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.cacheSaved
        ? 'Profil akun berhasil disimpan.' : 'Profil berhasil disimpan. Cache lokal belum diperbarui; muat ulang saat koneksi tersedia.')));
    } catch (e) {
      if (mounted && _sameSession) setState(() { _error = profileError(e); _uncertainSave = e is TimeoutException; });
    } finally { if (mounted) setState(() => _saving = false); }
  }
  Future<void> _link() async {
    if (_busy || _loading || !_sameSession) return;
    if (_dirty) {
      setState(() => _error = 'Simpan atau batalkan perubahan nama/foto sebelum membuka tautan jemaat.'); return;
    }
    setState(() => _navigating = true);
    try {
      await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SinkronisasiJemaatPage(returnToProfile: true, gateway: _gateway)));
    } finally { if (mounted) setState(() => _navigating = false); }
    if (mounted && _sameSession) await _reload();
  }
  Future<void> _logout() async {
    if (_busy) return;
    setState(() => _leaving = true);
    final confirmed = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('Keluar dari akun?'), content: Text(_dirty ? 'Perubahan nama atau foto yang belum disimpan akan dibuang.' : 'Anda akan keluar dari aplikasi.'), actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Ya, keluar')),
      ]));
    if (!mounted) return;
    if (confirmed != true) { setState(() => _leaving = false); return; }
    try {
      await _gateway.logout();
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (e) {
      if (!mounted) return;
      if (_gateway.signedInUid == null) { Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false); }
      else { setState(() => _error = profileError(e)); }
    } finally { if (mounted) setState(() => _leaving = false); }
  }
  Future<void> _back() async {
    if (_busy) return;
    if (!_dirty) { Navigator.pop(context); return; }
    setState(() => _confirmingExit = true);
    final discard = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(title: const Text('Buang perubahan?'),
      content: const Text('Nama atau foto belum disimpan.'), actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Lanjut edit')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Buang')),
      ]));
    if (!mounted) return;
    setState(() => _confirmingExit = false);
    if (discard == true) Navigator.pop(context);
  }
  Widget _notice(String text, {VoidCallback? retry}) => Card(color: Colors.orange.shade50, child: Padding(padding: const EdgeInsets.all(16), child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [Text(text), if (retry != null) TextButton.icon(onPressed: retry, icon: const Icon(Icons.refresh), label: const Text('Coba lagi'))])));
  Widget _info(IconData icon, String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, color: Colors.indigo), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)), Text(value.isEmpty ? '-' : value),
    ]))]));
  @override Widget build(BuildContext context) {
    final account = _account, book = _book.data;
    final photo = _sameSession ? profileDisplayPhoto(uid: _sessionUid!, accountPhoto: _useBookPhoto ? null : account?.photo, bookPhoto: book?['fotoProfil']) : null;
    return PopScope(canPop: !_busy && !_dirty, onPopInvokedWithResult: (didPop, _) { if (!didPop && !_busy) _back(); }, child: Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), appBar: AppBar(title: const Text('Profil Saya'), backgroundColor: Colors.indigo[900], foregroundColor: Colors.white,
        leading: IconButton(onPressed: _busy ? null : _back, icon: const Icon(Icons.arrow_back)),
        actions: [IconButton(tooltip: 'Muat ulang profil', onPressed: _busy || _loading || !_sameSession ? null : _reload, icon: const Icon(Icons.refresh))]),
      body: !_sameSession ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Sesi login berakhir atau akun berubah. Silakan masuk ulang.'), TextButton(onPressed: _leaving ? null : () => Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false), child: const Text('Masuk ulang')),
      ]))) : ListView(padding: const EdgeInsets.all(24), children: [
        if (_loading || _saving || _picking || _leaving) const LinearProgressIndicator(),
        if (_error != null) _notice(_error!, retry: _busy || _loading ? null : _reload),
        if (_uncertainSave) _notice('Pengiriman ulang dinonaktifkan agar tidak menimpa hasil yang mungkin sudah tersimpan. Tutup halaman lalu periksa profil terbaru.'),
        const SizedBox(height: 16), Center(child: ClipOval(child: SizedBox(width: 130, height: 130,
          child: _image != null ? Image.file(_image!, fit: BoxFit.cover) : photo == null
            ? ColoredBox(color: Colors.grey.shade200, child: const Icon(Icons.person, size: 65))
            : CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover, placeholder: (_, __) => const Center(child: CircularProgressIndicator()), errorWidget: (_, __, ___) => const Icon(Icons.person, size: 65))))),
        TextButton.icon(onPressed: _busy || _loading || _uncertainSave ? null : _pick, icon: const Icon(Icons.camera_alt), label: const Text('Ganti foto akun')),
        if (book != null && profilePhoto(book['fotoProfil']) != null) TextButton(onPressed: _busy || _loading || _uncertainSave ? null : () => setState(() { _image = null; _useBookPhoto = true; }), child: const Text('Gunakan foto buku induk')),
        if (_image != null || _useBookPhoto) TextButton(onPressed: _busy ? null : () => setState(() { _image = null; _useBookPhoto = false; }), child: const Text('Batalkan pilihan foto')),
        Center(child: Text((account?.role.isNotEmpty ?? false) ? account!.role.toUpperCase() : 'JEMAAT')),
        if (account != null) _info(Icons.church, 'Gereja asal akun', account.churchName.isNotEmpty ? account.churchName : account.churchId),
        if (account != null && !account.linked) _notice('Akun belum terhubung ke buku induk gereja.'),
        if (account != null && !account.linked) ElevatedButton.icon(onPressed: _busy || _loading ? null : _link, icon: const Icon(Icons.link), label: const Text('HUBUNGKAN DATA JEMAAT')),
        if (_bookError != null) _notice(_bookError!, retry: _busy || _loading ? null : _reload),
        if (_book.message != null) _notice(_book.message!),
        if (book != null) Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Data Buku Induk', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
          _info(Icons.person, 'Nama jemaat tertaut', profileText(book['namaLengkap'])),
          _info(Icons.cake, 'Tanggal lahir', profileDateText(book['tanggalLahir'])),
          _info(Icons.wc, 'Jenis kelamin', profileText(book['jenisKelamin'])),
          _info(Icons.phone, 'Nomor telepon', profileText(book['nomorTelepon'])),
          _info(Icons.location_on, 'Alamat', profileText(book['alamat'])),
          _info(Icons.water_drop, 'Status baptis', profileText(book['statusBaptis'])),
          _info(Icons.favorite, 'Status pernikahan', profileText(book['statusPernikahan'])),
          _info(Icons.family_restroom, 'Status keluarga', profileText(book['statusKeluarga'] ?? book['hubunganKeluarga'])),
          _info(Icons.groups, 'Kelompok / kategorial', profileText(book['kelompok'])),
          _info(Icons.star, 'Karunia pelayanan', profileText(book['karuniaPelayanan'])),
          const Text('Untuk koreksi biodata atau tautan, hubungi Admin Gereja.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]))),
        const SizedBox(height: 24), const Text('Pengaturan Akun Aplikasi', style: TextStyle(fontWeight: FontWeight.bold)),
        TextField(controller: _name, enabled: !_busy && !_loading && account != null && !_uncertainSave, maxLength: 120,
          onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Nama tampilan akun', prefixIcon: Icon(Icons.person_outline))),
        const Text('Nama tampilan akun tidak mengubah nama resmi di buku induk.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16), ElevatedButton(onPressed: _busy || _loading || account == null || _uncertainSave ? null : _save, child: const Text('SIMPAN NAMA & FOTO')),
        if (_dirty) TextButton(onPressed: _busy ? null : () => setState(() { _name.text = _account!.name; _image = null; _useBookPhoto = false; }), child: const Text('Batalkan perubahan')),
        TextButton.icon(onPressed: _busy ? null : _logout, icon: const Icon(Icons.logout, color: Colors.red), label: const Text('Keluar dari akun')),
      ]),
    ));
  }
}
