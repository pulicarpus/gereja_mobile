import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'pengurus_support.dart';
import 'pengurus_widgets.dart';
import 'user_manager.dart';

class RegionDiscussionPage extends StatefulWidget {
  final String postId;
  final String area;
  const RegionDiscussionPage({
    super.key,
    required this.postId,
    required this.area,
  });
  @override
  State<RegionDiscussionPage> createState() => _RegionDiscussionPageState();
}

class _RegionDiscussionPageState extends State<RegionDiscussionPage> {
  final _text = TextEditingController();
  final _uid = FirebaseAuth.instance.currentUser?.uid;
  late final _post = FirebaseFirestore.instance
      .collection('info_surat_daerah')
      .doc(widget.postId);
  late final _postStream = _post.snapshots();
  late final _comments = _post.collection('komentar');
  int _limit = 100;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stream = _comments
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots();
  bool _busy = false;
  String? _error;
  DocumentReference<Map<String, dynamic>>? _pending;
  Map<String, dynamic>? _payload;

  bool get _sameSession =>
      _uid != null &&
      FirebaseAuth.instance.currentUser?.uid == _uid &&
      UserManager().userId == _uid;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !_sameSession) return;
    final body = _text.text.trim();
    if (_pending == null && (body.isEmpty || body.length > 2000)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_pending == null) {
        final account = await FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 20));
        if (!_sameSession ||
            !account.exists ||
            account.data()?['isBlocked'] == true) {
          throw StateError(
            'Sesi atau izin akun berubah. Buka kembali halaman ini.',
          );
        }
        final name = pengurusText(account.data()?['namaLengkap']).trim();
        _payload = {
          'authorId': _uid,
          'authorName': name.isEmpty ? 'Pengguna' : name,
          'text': body,
          'createdAt': FieldValue.serverTimestamp(),
        };
        _pending = _comments.doc();
      }
      await FirebaseFirestore.instance
          .runTransaction((tx) async {
            final parent = await tx.get(_post);
            final existing = await tx.get(_pending!);
            if (!_sameSession) throw StateError('Sesi login berubah.');
            if (!parent.exists || parent.data()?['daerah'] != widget.area) {
              throw StateError('Postingan sudah dihapus atau daerah berubah.');
            }
            if (existing.exists) {
              if (existing.data()?['authorId'] != _payload!['authorId'] ||
                  existing.data()?['text'] != _payload!['text']) {
                throw StateError(
                  'Pesan tidak cocok. Buka kembali halaman diskusi.',
                );
              }
              return; // The same ID makes retry after an uncertain timeout safe.
            }
            tx.set(_pending!, _payload!);
          })
          .timeout(const Duration(seconds: 30));
      _pending = null;
      _payload = null;
      if (mounted) _text.clear();
    } catch (e) {
      if (e is StateError ||
          (e is FirebaseException &&
              [
                'permission-denied',
                'not-found',
                'invalid-argument',
              ].contains(e.code))) {
        _pending = null;
        _payload = null;
      }
      if (mounted)
        _error = _pending == null
            ? pengurusError(e)
            : 'Hasil kirim belum dapat dipastikan. Tekan kirim lagi untuk memeriksa pesan yang sama.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(DocumentReference<Map<String, dynamic>> ref) async {
    if (_busy || !_sameSession) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus komentar?'),
        content: const Text('Komentar ini akan dihapus dari diskusi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_sameSession) return;
    setState(() => _busy = true);
    try {
      await ref.delete().timeout(const Duration(seconds: 20));
    } catch (e) {
      if (mounted) setState(() => _error = pengurusError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Diskusi Info & Surat'),
      backgroundColor: Colors.indigo.shade900,
      foregroundColor: Colors.white,
    ),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _postStream,
      builder: (context, parent) {
        if (parent.hasError)
          return pengurusMessage(pengurusError(parent.error!));
        if (!parent.hasData)
          return const Center(child: CircularProgressIndicator());
        if (!parent.data!.exists ||
            parent.data!.data()?['daerah'] != widget.area) {
          return pengurusMessage('Postingan sudah tidak tersedia.');
        }
        final post = parent.data!.data()!;
        return SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.indigo.shade50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pengurusText(post['judul']),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.area,
                      style: const TextStyle(color: Colors.indigo),
                    ),
                    if (pengurusText(post['isi']).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        pengurusText(post['isi']),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _stream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError)
                      return pengurusMessage(pengurusError(snapshot.error!));
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty)
                      return const Center(
                        child: Text(
                          'Belum ada komentar. Mulai diskusi atau ajukan pertanyaan.',
                        ),
                      );
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: docs.length + (docs.length >= _limit ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == docs.length) {
                          return TextButton(
                            onPressed: () => setState(() {
                              _limit += 100;
                              _stream = _comments
                                  .orderBy('createdAt', descending: true)
                                  .limit(_limit)
                                  .snapshots();
                            }),
                            child: const Text('Muat komentar sebelumnya'),
                          );
                        }
                        final data = docs[index].data();
                        final mine = data['authorId'] == _uid;
                        final created = data['createdAt'];
                        final canDelete =
                            _sameSession &&
                            (mine || UserManager().canEditRegion(widget.area));
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: Card(
                              color: mine ? Colors.indigo.shade50 : null,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pengurusText(data['authorName']),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    SelectableText(pengurusText(data['text'])),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          created is Timestamp
                                              ? DateFormat(
                                                  'dd MMM HH:mm',
                                                ).format(created.toDate())
                                              : 'Mengirim…',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        if (canDelete)
                                          IconButton(
                                            tooltip: 'Hapus komentar',
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 18,
                                            ),
                                            onPressed: _busy
                                                ? null
                                                : () => _delete(
                                                    docs[index].reference,
                                                  ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (!_sameSession)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Sesi berubah. Buka kembali halaman ini.'),
                ),
              if (_sameSession)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _text,
                          enabled: !_busy && _pending == null,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 2000,
                          decoration: const InputDecoration(
                            hintText: 'Tulis komentar atau pertanyaan…',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Kirim komentar',
                        onPressed: _busy ? null : _send,
                        icon: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
