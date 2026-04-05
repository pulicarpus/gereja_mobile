import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // Wajib untuk TapGestureRecognizer (teks bisa diklik)
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'bible_models.dart';

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

  @override
  void initState() { super.initState(); _loadNotes(); }

  void _loadNotes() {
    final keys = widget.prefs.getStringList("ALL_NOTE_KEYS") ?? [];
    List<NoteModel> temp = [];
    for (var k in keys) {
      String? raw = widget.prefs.getString(k);
      if (raw != null) temp.add(NoteModel.fromRaw(k, raw));
    }
    temp.sort((a, b) => b.key.compareTo(a.key));
    setState(() { _allNotes = temp; _filteredNotes = temp; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Catatan Saya"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.grey[100]
              ),
              onChanged: (q) => setState(() => _filteredNotes = _allNotes.where((n) => 
                n.title.toLowerCase().contains(q.toLowerCase()) || 
                n.content.toLowerCase().contains(q.toLowerCase())
              ).toList()),
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
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        title: Text(note.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Text("${note.nas}\n${note.date}", style: const TextStyle(height: 1.4)),
                        isThreeLine: true,
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (c) => NoteEditorPage(
                              nas: note.nas, 
                              existingKey: note.key, 
                              prefs: widget.prefs,
                              db: widget.db,
                              allBooks: widget.allBooks,
                            )
                          )).then((res) {
                            if (res != null) {
                              Navigator.pop(context, res);
                            } else {
                              _loadNotes(); 
                            }
                          });
                        },
                        onLongPress: () => _confirmDelete(note.key),
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
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("Hapus Catatan?"),
      content: const Text("Catatan ini tidak dapat dikembalikan setelah dihapus."),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("BATAL", style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () async {
            List<String> keys = widget.prefs.getStringList("ALL_NOTE_KEYS") ?? [];
            keys.remove(key);
            await widget.prefs.setStringList("ALL_NOTE_KEYS", keys);
            await widget.prefs.remove(key);
            Navigator.pop(context);
            _loadNotes();
          }, 
          child: const Text("HAPUS", style: TextStyle(color: Colors.white))
        ),
      ],
    ));
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

  @override
  void initState() {
    super.initState();
    
    _isEditing = widget.existingKey == null; 
    
    String t = "", p = "", c = "";
    _currentDate = DateFormat('dd MMMM yyyy').format(DateTime.now());

    if (widget.existingKey != null) {
      String raw = widget.prefs.getString(widget.existingKey!) ?? "";
      List<String> parts = raw.split("~|~");
      
      t = parts.length > 1 ? parts[1] : "";
      p = parts.length > 2 && parts[2].trim().isNotEmpty ? parts[2] : ""; 
      _currentDate = parts.length > 3 ? parts[3] : _currentDate;
      c = parts.length > 5 ? parts[5] : "";
    }

    _titleCtrl = TextEditingController(text: t);
    _preacherCtrl = TextEditingController(text: p);
    _contentCtrl = TextEditingController(text: c);
  }

  void _saveNote() async {
    String key = widget.existingKey ?? "Note_${DateTime.now().millisecondsSinceEpoch}";
    String data = "${widget.nas}~|~${_titleCtrl.text}~|~${_preacherCtrl.text}~|~$_currentDate~|~ ~|~${_contentCtrl.text}";
    
    List<String> keys = widget.prefs.getStringList("ALL_NOTE_KEYS") ?? [];
    if (!keys.contains(key)) keys.add(key);
    
    await widget.prefs.setStringList("ALL_NOTE_KEYS", keys);
    await widget.prefs.setString(key, data);
    
    setState(() {
      _isEditing = false; 
    });
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Catatan disimpan!")));
  }

  // DIUBAH: Sekarang menerima parameter opsional (Bisa ayat utama, bisa ayat di dalam isi teks)
  void _showFloatingAyat({String? customNas}) async {
    // Gunakan customNas jika ada (saat di-klik dari dalam teks), jika tidak gunakan nas utama
    String nasToSearch = customNas ?? widget.nas;

    final regex = RegExp(r'(.+?)\s+(\d+):(\d+)(?:-(\d+))?');
    final match = regex.firstMatch(nasToSearch);

    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Format ayat tidak dapat dibaca database")));
      return;
    }

    String bookName = match.group(1)!;
    int chap = int.parse(match.group(2)!);
    int startVerse = int.parse(match.group(3)!);
    int? endVerse = match.group(4) != null ? int.parse(match.group(4)!) : startVerse;

    int bookNum = -1;
    try {
      bookNum = widget.allBooks.firstWhere((b) => b.name.toLowerCase() == bookName.toLowerCase() || b.shortName.toLowerCase() == bookName.toLowerCase()).bookNumber;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Kitab tidak ditemukan")));
      return;
    }

    final List<Map<String, dynamic>> results = await widget.db.query(
      'verses',
      where: 'book_number = ? AND chapter = ? AND verse >= ? AND verse <= ?',
      whereArgs: [bookNum, chap, startVerse, endVerse],
      orderBy: 'verse ASC'
    );

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(nasToSearch, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (ctx, i) {
                    var r = results[i];
                    String cleanText = r['text'].toString().replaceAll(RegExp(r'<[^>]*>'), '');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: RichText(
                        text: TextSpan(style: const TextStyle(color: Colors.black, fontSize: 16, height: 1.4), children: [
                          TextSpan(text: "${r['verse']}. ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                          TextSpan(text: cleanText),
                        ])
                      ),
                    );
                  }
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.menu_book),
                  label: const Text("MENUJU KE PASAL INI"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo[900], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context, {'book_number': bookNum, 'chapter': chap, 'verse': startVerse});
                  },
                ),
              )
            ],
          ),
        );
      }
    );
  }

  // FUNGSI BARU: Mendeteksi nama kitab di dalam isi teks dan mengubahnya jadi Link biru
  Widget _buildClickableContent(String text) {
    // Mengumpulkan semua nama dan singkatan kitab dari Database untuk dijadikan target Regex
    List<String> bookNames = [];
    for (var b in widget.allBooks) {
      bookNames.add(RegExp.escape(b.name));
      bookNames.add(RegExp.escape(b.shortName));
    }
    
    // Pola Regex pintar: Hanya mendeteksi jika teks adalah [Nama Kitab di Database] [Angka]:[Angka]-[Angka]
    String pattern = r'(' + bookNames.join('|') + r')\s+(\d+):(\d+)(?:-(\d+))?';
    RegExp exp = RegExp(pattern, caseSensitive: false);

    List<InlineSpan> spans = [];

    text.splitMapJoin(
      exp,
      onMatch: (Match m) {
        String fullRef = m.group(0)!; // Contoh: "Lukas 2:3-4"
        spans.add(TextSpan(
          text: fullRef,
          style: const TextStyle(
            color: Colors.blue, 
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.underline
          ),
          recognizer: TapGestureRecognizer()..onTap = () {
            // Ketika diklik, panggil Floating Ayat dengan referensi ayat yang diklik
            _showFloatingAyat(customNas: fullRef); 
          }
        ));
        return "";
      },
      onNonMatch: (String nonMatchText) {
        // Teks biasa
        spans.add(TextSpan(text: nonMatchText, style: const TextStyle(color: Colors.black87)));
        return "";
      }
    );

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 16, height: 1.6),
        children: spans
      )
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
            IconButton(icon: const Icon(Icons.save), onPressed: _saveNote)
          else
            IconButton(icon: const Icon(Icons.edit), onPressed: () => setState(() => _isEditing = true))
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TOMBOL FLOATING AYAT UTAMA (Ayat yang di-mark)
            InkWell(
              onTap: () => _showFloatingAyat(), // Panggil tanpa parameter untuk ayat utama
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3))
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_stories, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Text(widget.nas, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 16)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: _isEditing ? _buildEditMode() : _buildReadMode(),
            ),
          ],
        ),
      ),
    );
  }

  // WIDGET KETIKA MODE BACA
  Widget _buildReadMode() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_titleCtrl.text.isEmpty ? "Tanpa Judul" : _titleCtrl.text, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Text(_preacherCtrl.text.isEmpty ? "-" : _preacherCtrl.text, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Text(_currentDate, style: const TextStyle(color: Colors.grey)),
            ],
          ),
          const Divider(height: 30, thickness: 1),
          // MENGGUNAKAN FUNGSI BARU UNTUK KONTEN BACAAN
          _buildClickableContent(_contentCtrl.text),
        ],
      ),
    );
  }

  // WIDGET KETIKA MODE EDIT
  Widget _buildEditMode() {
    return Column(
      children: [
        TextField(
          controller: _titleCtrl, 
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(labelText: "Judul Khotbah/Catatan", border: OutlineInputBorder())
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _preacherCtrl, 
          decoration: const InputDecoration(labelText: "Nama Pengkhotbah (Opsional)", prefixIcon: Icon(Icons.person), border: OutlineInputBorder())
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(5)),
            child: TextField(
              controller: _contentCtrl, 
              maxLines: null, 
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(hintText: "Tulis isi catatan di sini...", border: InputBorder.none)
            ),
          )
        ),
      ],
    );
  }
}