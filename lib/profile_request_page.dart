import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'approval_service.dart';
import 'user_manager.dart';
import 'management_support.dart';

class ProfileRequestPage extends StatefulWidget {
  const ProfileRequestPage({super.key});
  @override State<ProfileRequestPage> createState() => _ProfileRequestPageState();
}
class _ProfileRequestPageState extends State<ProfileRequestPage> {
  late final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  late final String? _church = UserManager().getChurchIdForCurrentView();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _requests = FirebaseFirestore.instance
    .collection('profile_requests').where('churchId', isEqualTo: _church).where('status', isEqualTo: 'pending').snapshots();
  String? _busy;
  bool get _current => _uid != null && FirebaseAuth.instance.currentUser?.uid == _uid &&
    UserManager().getChurchIdForCurrentView() == _church;
  Future<void> _review(QueryDocumentSnapshot<Map<String, dynamic>> row, bool approve) async {
    if (_busy != null || !_current) return;
    final d = row.data();
    final confirmed = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(approve ? 'Setujui permohonan?' : 'Tolak permohonan?'),
      content: Text(approve
        ? 'Pastikan identitas ${managementText(d['namaLengkap'])} telah diperiksa secara langsung.\n'
          '${d['kind'] == 'link' ? 'Buku induk: ${managementText(d['bookName'])}' : 'Pendaftaran anggota gereja'}'
        : 'Pemohon dapat mengirim ulang setelah permohonan ditolak.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(approve ? 'Identitas sudah diperiksa, setujui' : 'Tolak'))]));
    if (confirmed != true || !mounted || !_current) return;
    setState(() => _busy = row.id);
    try {
      final result = await ApprovalService().call('reviewProfileRequest', {'requestId': row.id, 'approve': approve});
      if (mounted && _current) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:
        Text(result['status'] == 'approved' ? 'Permohonan disetujui.' : 'Permohonan ditolak.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(managementError(e))));
    } finally { if (mounted) setState(() => _busy = null); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Persetujuan Anggota & Tautan')),
    body: !_current || _church == null || _church!.isEmpty ? const Center(child: Text('Sesi atau gereja berubah. Buka ulang halaman.'))
      : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: _requests, builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Permohonan tidak dapat dimuat. Periksa izin atau konfigurasi layanan.'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snapshot.data!.docs;
        if (rows.isEmpty) return const Center(child: Text('Tidak ada permohonan menunggu.'));
        return ListView(children: [const Padding(padding: EdgeInsets.all(16),
          child: Text('Periksa identitas pemohon dan buku induk sebelum menyetujui.')),
          for (final row in rows) Card(child: ListTile(
            title: Text(managementText(row.data()['namaLengkap'], 'Tanpa nama')),
            subtitle: Text('${managementText(row.data()['email'])}\n'
              '${row.data()['emailVerified'] == true ? 'Email terverifikasi' : 'Email belum terverifikasi'} • UID: ${managementText(row.data()['uid'])}\n'
              '${row.data()['kind'] == 'link' ? 'Tautan: ${managementText(row.data()['bookName'])}' : 'Pendaftaran gereja'}'),
            trailing: _busy == row.id ? const CircularProgressIndicator() : Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(onPressed: _busy == null ? () => _review(row, false) : null, icon: const Icon(Icons.close)),
              IconButton(onPressed: _busy == null ? () => _review(row, true) : null, icon: const Icon(Icons.check))])))]);
      }));
}
