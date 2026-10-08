# Editor gambar ayat

Dari Alkitab, pilih ayat lalu Buat Gambar. Editor menyediakan:

- Edit ayat, referensi, dan teks tambahan.
- Font standar/serif/monospace, ukuran, jarak baris, tebal, miring, bayangan, perataan, dan warna.
- Latar gradasi, warna polos, foto perangkat, dan pencarian Pixabay. Pencarian online tidak menghalangi pemakaian editor offline.
- Zoom serta pergeseran foto, lapisan gelap, posisi/lebar teks, dan drag teks di pratinjau.
- Story 9:16, kotak 1:1, feed 4:5, lanskap 16:9; watermark opsional.
- Undo/redo sampai 80 langkah dan pengembalian desain awal yang dapat di-undo.

Ekspor menggunakan kanvas desain yang sama dengan pratinjau pada lebar 1080 piksel. Teks yang sangat panjang diperkecil agar tidak terpotong. Simpan PNG membuka pilihan lokasi di Windows; pada Android menyimpan ke galeri. Bagikan memakai dialog berbagi sistem. Hasil dapat disimpan terlebih dahulu bila aplikasi tujuan tidak muncul pada dialog berbagi Windows.

Foto dipilih dari perangkat tanpa diunggah. Perubahan editor belum disimpan sebagai proyek setelah halaman ditutup. Jenis font serif/monospace memakai font sistem yang tersedia.

Validasi: flutter test test/verse_image_editor_test.dart. Tes mencakup undo/redo, edit teks, tampilan layar kecil dengan ayat panjang, pilihan latar/rasio, dan ukuran PNG yang dihasilkan renderer ekspor.
