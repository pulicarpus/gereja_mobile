// Fungsi untuk mencari kata di Alkitab
Future<List<Map<String, dynamic>>> searchBible(String query) async {
  if (_db == null) return [];
  // Mencari kata yang mengandung query, limit 100 agar tidak lag
  return await _db!.rawQuery('''
    SELECT v.*, b.long_name 
    FROM verses v 
    JOIN books b ON v.book_number = b.book_number 
    WHERE v.text LIKE ? 
    LIMIT 100
  ''', ['%$query%']);
}

// Fungsi Catatan (Simpan ke Table baru 'notes')
// Jalankan query ini sekali saat init: 
// CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, book_id INTEGER, chapter INTEGER, verse INTEGER, content TEXT, date TEXT)