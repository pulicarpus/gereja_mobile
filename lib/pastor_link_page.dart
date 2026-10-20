import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'church_pastors.dart';
import 'management_support.dart';
import 'pastor_link_service.dart';

class PastorLinkPage extends StatefulWidget {
  final ManagementRecord account;
  const PastorLinkPage({super.key, required this.account});
  @override
  State<PastorLinkPage> createState() => _PastorLinkPageState();
}

class _PastorLinkPageState extends State<PastorLinkPage> {
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _members;
  List<ChurchPastor> _profiles = [];
  String? _memberId, _profileId, _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ref = FirebaseFirestore.instance
          .collection('churches')
          .doc(managementText(widget.account.data['churchId']));
      final church = await ref.get(const GetOptions(source: Source.server));
      final members = await ref
          .collection('jemaat')
          .get(const GetOptions(source: Source.server));
      if (!mounted) return;
      setState(() {
        _members = members.docs
            .where(
              (d) =>
                  d.data()['status'] != 'Meninggal' &&
                  (managementText(d.data()['uid']).isEmpty ||
                      d.data()['uid'] == widget.account.id),
            )
            .toList();
        _profiles = churchPastors(
          church.data() ?? {},
        ).where((p) => p.uid.isEmpty || p.uid == widget.account.id).toList();
        final linked = managementText(widget.account.data['jemaatId']);
        _memberId = _members!.any((m) => m.id == linked) ? linked : null;
        final owned = _profiles.where((p) => p.uid == widget.account.id);
        _profileId = owned.length == 1 ? owned.single.id : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy ||
        _memberId == null ||
        (_profiles.isNotEmpty && _profileId == null))
      return;
    final member = _members!.firstWhere((m) => m.id == _memberId);
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hubungkan akun gembala?'),
        content: Text(
          'Akun: ${managementText(widget.account.data['namaLengkap'])}\n'
          'Data Jemaat: ${managementText(member.data()['namaLengkap'])}\n\n'
          'Akun ini akan menjadi admin gereja dan dapat melihat fitur daerah. '
          'Pastikan akun dan profil adalah orang yang sama.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hubungkan'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PastorLinkService().link(
        widget.account,
        _memberId!,
        _profileId ?? '',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = managementError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Hubungkan Gembala')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Pilih Data Jemaat dan profil gembala milik akun ini. Profil yang sudah ada tetap dipakai.',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_members != null) ...[
            DropdownButtonFormField<String>(
              value: _memberId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Data Jemaat'),
              items: _members!
                  .map(
                    (m) => DropdownMenuItem(
                      value: m.id,
                      child: Text(
                        managementText(m.data()['namaLengkap']),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _busy ? null : (v) => setState(() => _memberId = v),
            ),
            if (_profiles.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _profileId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Profil gembala yang sudah ada',
                ),
                items: _profiles
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: _busy ? null : (v) => setState(() => _profileId = v),
              ),
            if (_profiles.isEmpty)
              const Text(
                'Jika gereja belum mempunyai profil gembala, profil dibuat dari Data Jemaat yang dipilih.',
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed:
                  _busy ||
                      _memberId == null ||
                      (_profiles.isNotEmpty && _profileId == null)
                  ? null
                  : _save,
              child: const Text('Hubungkan dan jadikan admin gereja'),
            ),
          ] else if (!_busy)
            TextButton(onPressed: _load, child: const Text('Coba lagi')),
        ],
      ),
    ),
  );
}
