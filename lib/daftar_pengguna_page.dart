import 'profile_request_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'detail_pengguna_page.dart';
import 'management_service.dart';
import 'management_support.dart';

class DaftarPenggunaPage extends StatefulWidget {
  final ManagementGateway? gateway;
  const DaftarPenggunaPage({super.key, this.gateway});
  @override State<DaftarPenggunaPage> createState() => _DaftarPenggunaPageState();
}
class _DaftarPenggunaPageState extends State<DaftarPenggunaPage> {
  late final ManagementGateway _gateway;
  late Stream<List<ManagementRecord>> _stream;
  StreamSubscription<String?>? _auth;
  final _search = TextEditingController();
  String _query = '';
  bool _expired = false;
  @override void initState() {
    super.initState();
    _gateway = widget.gateway ?? FirebaseManagementGateway();
    final uid = _gateway.signedInUid;
    _stream = _gateway.users();
    _auth = _gateway.authChanges.listen((id) {
      if (mounted && id != uid) setState(() => _expired = true);
    });
  }
  @override void dispose() { _auth?.cancel(); _search.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Manajemen Pengguna'), actions: [IconButton(tooltip: 'Persetujuan anggota dan tautan', icon: const Icon(Icons.how_to_reg), onPressed: _expired ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileRequestPage())))]),
    body: _expired ? const Center(child: Text('Sesi berubah. Silakan masuk ulang.')) : Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _search,
        onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
        decoration: InputDecoration(labelText: 'Cari nama atau email', prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { _search.clear(); setState(() => _query = ''); })))),
      Expanded(child: StreamBuilder<List<ManagementRecord>>(stream: _stream, builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(managementError(snapshot.error!), textAlign: TextAlign.center)),
          TextButton(onPressed: () => setState(() => _stream = _gateway.users()), child: const Text('Coba lagi'))]));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final records = snapshot.data!.where((item) => _query.isEmpty ||
          managementText(item.data['namaLengkap']).toLowerCase().contains(_query) ||
          managementText(item.data['email']).toLowerCase().contains(_query)).toList()
          ..sort((a, b) => managementText(a.data['namaLengkap']).compareTo(managementText(b.data['namaLengkap'])));
        if (records.isEmpty) return Center(child: Text(_query.isEmpty ? 'Belum ada pengguna di gereja ini.' : 'Nama atau email tidak ditemukan.'));
        return ListView.builder(itemCount: records.length, itemBuilder: (context, index) {
          final user = records[index], data = user.data;
          return Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(managementText(data['namaLengkap'], 'Tanpa Nama')),
            subtitle: Text('${managementText(data['email'], 'Tidak ada email')}\n'
              '${managementText(data['role'], 'user').toUpperCase()} • ${managementText(data['kelompok'], 'Belum diatur')}'
              '${managementText(data['adminDaerahArea']).isEmpty ? '' : '\nPengurus Daerah: ${managementText(data['adminDaerahArea'])}'}'
              '${data['isBlocked'] == true ? '\nAkun dinonaktifkan' : ''}'),
            trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => DetailPenggunaPage(userId: user.id, gateway: _gateway)))));
        });
      }))]));
}

