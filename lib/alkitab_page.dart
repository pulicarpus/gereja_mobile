// Fungsi navigasi pilih Kitab yang lebih akurat
  void _showBookPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Supaya bisa di-scroll penuh
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        child: ListView.builder(
          itemCount: _allBooks.length,
          itemBuilder: (context, i) {
            final b = _allBooks[i];
            return ListTile(
              title: Text(b['long_name'] ?? b['name']),
              onTap: () {
                Navigator.pop(context);
                int rawId = b['book_number'] ?? b['book_id'];
                // Normalisasi ID ke 1-66
                setState(() {
                  _bookId = (rawId >= 10) ? (rawId / 10).round() : rawId;
                  _bookName = b['long_name'] ?? b['name'];
                });
                _showChapterPicker();
              },
            );
          },
        ),
      ),
    );
  }

  // Fungsi navigasi pilih Pasal yang mengambil jumlah pasal asli dari DB
  Future<void> _showChapterPicker() async {
    // Ambil jumlah pasal maksimum untuk kitab ini dari database
    int maxChapter = 50; // Default
    try {
      // Kita hitung jumlah pasal unik dari tabel verses untuk kitab yang dipilih
      List<Map<String, dynamic>> columnInfo = await _db!.rawQuery("PRAGMA table_info(verses)");
      String bookCol = columnInfo.any((c) => c['name'] == 'book_number') ? 'book_number' : 'book_id';
      int targetId = (bookCol == 'book_number') ? _bookId * 10 : _bookId;

      var result = await _db!.rawQuery(
        "SELECT MAX(chapter) as max_chap FROM verses WHERE $bookCol = ?", [targetId]
      );
      if (result.isNotEmpty && result.first['max_chap'] != null) {
        maxChapter = result.first['max_chap'] as int;
      }
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      builder: (context) => GridView.builder(
        padding: const EdgeInsets.all(15),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemCount: maxChapter, 
        itemBuilder: (context, i) => InkWell(
          onTap: () {
            setState(() => _chapter = i + 1);
            _loadData();
            Navigator.pop(context);
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: Text("${i + 1}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ),
        ),
      ),
    );
  }