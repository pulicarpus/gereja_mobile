import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 👈 WAJIB UNTUK CLOUD
import 'package:firebase_auth/firebase_auth.dart'; // 👈 WAJIB UNTUK CLOUD

import 'bible_models.dart';
import 'bible_local_store.dart';
import 'bible_support.dart';

class NoteListPage extends StatefulWidget {
  final SharedPreferences prefs;
  final Database db;
  final List<BibleBook> allBooks;

  const NoteListPage({
    super.key,
    required this.prefs,
    required this.db,
    required this.allBooks,
  });

  @override
  State<NoteListPage> createState() => _NoteListPageState();
}

class _NoteListPageState extends State<NoteListPage> {
  List<NoteModel> _allNotes = [];
  List<NoteModel> _filteredNotes = [];
  final _searchCtrl = TextEditingController();
  late BibleLocalStore _store;
  bool _isSyncing = false; // Indikator loading awan

  @override
  void initState() {
    super.initState();
    _store = BibleLocalStore(
      widget.prefs,
      FirebaseAuth.instance.currentUser?.uid,
    );
    _loadNotes();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _importLegacy() async {
    if (_isSyncing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Impor catatan perangkat lama'),
        content: const Text(
          'Catatan lama belum memiliki identitas pemilik. Impor hanya jika catatan dan stabilo tersebut milik Anda. Sumber lama tetap disimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Milik saya, impor'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      await _store.importLegacyNotes();
      await _store.importLegacyHighlights();
      if (mounted) _loadNotes();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impor gagal. Sumber lama masih tersimpan.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _loadNotes() {
    if (!mounted) return;
    final keys = _store.noteKeys;
    List<NoteModel> temp = [];
    for (var k in keys) {
      String? raw = _store.readNote(k);
      if (raw != null) temp.add(NoteModel.fromRaw(k, raw));
    }
    temp.sort((a, b) => b.key.compareTo(a.key));
    setState(() {
      _allNotes = temp;
      final q = _searchCtrl.text.toLowerCase();
      _filteredNotes = temp
          .where(
            (n) =>
                n.title.toLowerCase().contains(q) ||
                n.content.toLowerCase().contains(q),
          )
          .toList();
    });
  }

  // 👇 FUNGSI BACKUP KE CLOUD (FIRESTORE) 👇
  Future<void> _backupToCloud() async {
    if (!mounted || _isSyncing) return;
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != _store.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠ Anda harus Login dulu untuk Backup ke Cloud!"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final keys = _store.noteKeys;
    if (keys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tidak ada catatan untuk dibackup.")),
      );
      return;
    }

    setState(() => _isSyncing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🚀 Mengunggah catatan ke Cloud...")),
    );

    try {
      // Kita pakai fungsi BATCH agar ratusan catatan bisa dikirim dalam 1 kedipan mata
      WriteBatch batch = FirebaseFirestore.instance.batch();
      CollectionReference notesRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notes');

      int pending = 0;
      for (var k in keys) {
        String rawData = _store.readNote(k) ?? "";
        if (rawData.isNotEmpty) {
          batch.set(notesRef.doc(k), {
            'key': k,
            'raw_data': NoteModel.fromRaw(k, rawData).toLegacyRaw(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          pending++;
          if (pending == 400) {
            if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
              throw StateError('Sesi berubah. Backup dihentikan.');
            }
            await batch.commit().timeout(const Duration(seconds: 45));
            batch = FirebaseFirestore.instance.batch();
            pending = 0;
          }
        }
      }

      if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
        throw StateError('Sesi berubah. Backup dihentikan.');
      }
      if (pending > 0)
        await batch.commit().timeout(
          const Duration(seconds: 45),
        ); // Eksekusi pengiriman massal

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "✅ Backup Cloud Berhasil! Aman dari HP rusak/hilang.",
            ),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Gagal backup: $e"),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  // 👇 FUNGSI RESTORE DARI CLOUD (FIRESTORE) 👇
  Future<void> _restoreFromCloud() async {
    if (!mounted || _isSyncing) return;
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != _store.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠ Anda harus Login dulu untuk Restore dari Cloud!"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSyncing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("☁ Mengunduh catatan dari Cloud...")),
    );

    try {
      // Sedot semua dokumen dari brankas user
      QuerySnapshot snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notes')
          .get()
          .timeout(const Duration(seconds: 25));

      if (snap.docs.isEmpty) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Tidak ada backup catatan di Cloud Anda."),
            ),
          );
        return;
      }

      if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
        throw StateError("Sesi berubah. Restore dihentikan.");
      }
      int restoredCount = 0;

      for (var doc in snap.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String key = data['key'] ?? doc.id;
        String rawData = data['raw_data'] ?? "";

        if (rawData.isNotEmpty) {
          // Restore melengkapi data, tanpa menimpa edit atau penghapusan lokal.
          if (_store.deletedKeys.contains(key) || _store.readNote(key) != null)
            continue;
          await _store.saveNote(
            key,
            NoteModel.fromRaw(key, rawData).toLocalJson(),
          );
          restoredCount++;
        }
      }

      _loadNotes(); // Segarkan layar
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "✅ $restoredCount Catatan berhasil disedot dari Cloud!",
            ),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Gagal restore: $e"),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Catatan Saya"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          if (_store.hasLegacyNotes)
            IconButton(
              icon: const Icon(Icons.move_to_inbox),
              tooltip: 'Impor catatan lama perangkat',
              onPressed: _isSyncing ? null : _importLegacy,
            ),
          // 👇 TOMBOL AWAN SULTAN 👇
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.cloud_download),
              tooltip: "Restore dari Cloud",
              onPressed: _restoreFromCloud,
            ),
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              tooltip: "Backup ke Cloud",
              onPressed: _backupToCloud,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: "Cari catatan...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onChanged: (q) => setState(
                () => _filteredNotes = _allNotes
                    .where(
                      (n) =>
                          n.title.toLowerCase().contains(q.toLowerCase()) ||
                          n.content.toLowerCase().contains(q.toLowerCase()),
                    )
                    .toList(),
              ),
            ),
          ),
          Expanded(
            child: _filteredNotes.isEmpty
                ? const Center(child: Text("Belum ada catatan."))
                : ListView.builder(
                    itemCount: _filteredNotes.length,
                    itemBuilder: (context, i) {
                      final note = _filteredNotes[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          title: Text(
                            note.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Text(
                            "${note.nas}\n${note.date}",
                            style: const TextStyle(height: 1.4),
                          ),
                          isThreeLine: true,
                          onTap: _isSyncing
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (c) => NoteEditorPage(
                                        nas: note.nas,
                                        existingKey: note.key,
                                        prefs: widget.prefs,
                                        db: widget.db,
                                        allBooks: widget.allBooks,
                                      ),
                                    ),
                                  ).then((res) {
                                    if (!mounted) return;
                                    if (res != null) {
                                      Navigator.pop(context, res);
                                    } else {
                                      _loadNotes();
                                    }
                                  });
                                },
                          onLongPress: _isSyncing
                              ? null
                              : () => _confirmDelete(note.key),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String key) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Hapus Catatan?"),
        content: const Text(
          "Catatan dihapus dari akun ini pada perangkat. Backup cloud tetap disimpan; aplikasi lama masih dapat memulihkannya.",
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("BATAL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await _store.deleteNote(key);
                if (!mounted || !c.mounted) return;
                Navigator.pop(c);
                _loadNotes();
              } catch (_) {
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Gagal menghapus catatan. Coba lagi.'),
                    ),
                  );
              }
            },
            child: const Text("HAPUS", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// HALAMAN VIEWER & EDITOR CATATAN
// =========================================================================
class NoteEditorPage extends StatefulWidget {
  final String nas;
  final String? existingKey;
  final SharedPreferences prefs;
  final Database db;
  final List<BibleBook> allBooks;

  const NoteEditorPage({
    super.key,
    required this.nas,
    this.existingKey,
    required this.prefs,
    required this.db,
    required this.allBooks,
  });

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late TextEditingController _titleCtrl;
  late TextEditingController _preacherCtrl;
  late TextEditingController _contentCtrl;

  bool _isEditing = false;
  String _currentDate = "";
  late BibleLocalStore _store;
  late String _noteKey;
  bool _isSaving = false;
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _preacherCtrl.dispose();
    _contentCtrl.dispose();
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    _store = BibleLocalStore(
      widget.prefs,
      FirebaseAuth.instance.currentUser?.uid,
    );
    _noteKey =
        widget.existingKey ?? "Note_${DateTime.now().microsecondsSinceEpoch}";
    _isEditing = widget.existingKey == null;

    String t = "", p = "", c = "";
    _currentDate = DateFormat('dd MMMM yyyy').format(DateTime.now());

    if (widget.existingKey != null) {
      final note = NoteModel.fromRaw(
        widget.existingKey!,
        _store.readNote(widget.existingKey!) ?? '',
      );
      t = note.title;
      p = note.preacher;
      _currentDate = note.date;
      c = note.content;
    }

    _titleCtrl = TextEditingController(text: t);
    _preacherCtrl = TextEditingController(text: p);
    _contentCtrl = TextEditingController(text: c);
  }

  Future<void> _saveNote() async {
    if (_isSaving) return;
    if (_titleCtrl.text.contains('~|~') ||
        _preacherCtrl.text.contains('~|~') ||
        _contentCtrl.text.contains('~|~')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gunakan pemisah lain selain ~|~ agar backup kompatibel dengan aplikasi lama.',
          ),
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final note = NoteModel(
        key: _noteKey,
        nas: widget.nas,
        title: _titleCtrl.text,
        preacher: _preacherCtrl.text,
        date: _currentDate,
        content: _contentCtrl.text,
        rawData: '',
      );
      await _store.saveNote(_noteKey, note.toLocalJson());
      if (!mounted) return;
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catatan disimpan di perangkat.')),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menyimpan. Coba lagi.')),
        );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showFloatingAyat({String? customNas}) async {
    String nasToSearch = customNas ?? widget.nas;

    final reference = BibleReference.parse(nasToSearch, widget.allBooks);
    if (reference == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Referensi ayat tidak dikenali.')),
      );
      return;
    }
    final bookNum = reference.bookId;
    final chap = reference.chapter;
    final startVerse = reference.verses.first;
    List<Map<String, dynamic>> results;
    try {
      final all = await widget.db.query(
        'verses',
        where: 'book_number = ? AND chapter = ?',
        whereArgs: [bookNum, chap],
        orderBy: 'verse ASC',
      );
      results = all
          .where((r) => reference.verses.contains(r['verse']))
          .toList();
      if (results.isEmpty) throw StateError('Ayat tidak tersedia.');
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ayat tidak dapat dimuat.')),
        );
      return;
    }

    if (!mounted) return;

    final destination = await showModalBottomSheet<Map<String, int>>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                nasToSearch,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (ctx, i) {
                    var r = results[i];
                    String cleanText = cleanBibleText(r['text'].toString());
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            height: 1.4,
                          ),
                          children: [
                            TextSpan(
                              text: "${r['verse']}. ",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                            TextSpan(text: cleanText),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.menu_book),
                  label: const Text("MENUJU KE PASAL INI"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo[900],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.pop(context, {
                      'book_number': bookNum,
                      'chapter': chap,
                      'verse': startVerse,
                    });
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (mounted && destination != null) Navigator.pop(context, destination);
  }

  Widget _buildClickableContent(String text) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    List<String> bookNames = [];
    for (var b in widget.allBooks) {
      bookNames.add(RegExp.escape(b.name.trim()));
      bookNames.add(RegExp.escape(b.shortName.trim()));
    }

    bookNames.sort((a, b) => b.length.compareTo(a.length));
    String pattern =
        r'(' +
        bookNames.join('|') +
        r')\s+(\d+):(\d+)(?:-(\d+))?(?:,\s*\d+(?:-\d+)?)*';
    RegExp exp = RegExp(pattern, caseSensitive: false);

    List<InlineSpan> spans = [];

    text.splitMapJoin(
      exp,
      onMatch: (Match m) {
        String fullRef = m.group(0)!;
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _showFloatingAyat(customNas: fullRef);
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: fullRef,
            style: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
            ),
            recognizer: recognizer,
          ),
        );
        return "";
      },
      onNonMatch: (String nonMatchText) {
        spans.add(
          TextSpan(
            text: nonMatchText,
            style: const TextStyle(color: Colors.black87),
          ),
        );
        return "";
      },
    );

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 16, height: 1.6),
        children: spans,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_isEditing ? "Edit Catatan" : "Catatan"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isSaving ? null : _saveNote,
            )
          else
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _showFloatingAyat(),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_stories,
                      color: Colors.blue,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.nas,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Expanded(child: _isEditing ? _buildEditMode() : _buildReadMode()),
          ],
        ),
      ),
    );
  }

  Widget _buildReadMode() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _titleCtrl.text.isEmpty ? "Tanpa Judul" : _titleCtrl.text,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                _preacherCtrl.text.isEmpty ? "-" : _preacherCtrl.text,
                style: const TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Text(_currentDate, style: const TextStyle(color: Colors.grey)),
            ],
          ),
          const Divider(height: 30, thickness: 1),
          _buildClickableContent(_contentCtrl.text),
        ],
      ),
    );
  }

  Widget _buildEditMode() {
    return Column(
      children: [
        TextField(
          controller: _titleCtrl,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            labelText: "Judul Khotbah/Catatan",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _preacherCtrl,
          decoration: const InputDecoration(
            labelText: "Nama Pengkhotbah (Opsional)",
            prefixIcon: Icon(Icons.person),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(5),
            ),
            child: TextField(
              controller: _contentCtrl,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: "Tulis isi catatan di sini...",
                border: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
