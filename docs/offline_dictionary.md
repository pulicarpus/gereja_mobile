# Kamus offline

Menu Kamus Alkitab memakai SQLite lokal. Paket saat ini berisi tiga definisi contoh yang disusun untuk menguji fitur, bukan isi Kamus SABDA. Sumber ditampilkan di setiap definisi. Pencarian AI lama tetap tersedia melalui ikon bintang di kanan atas dan membutuhkan internet.

Untuk memasukkan materi yang telah diizinkan, siapkan JSON berupa daftar objek dengan `term`, `definition` (teks biasa), `source`, dan `references` (daftar rujukan, misalnya `Matius 22:37-39`). Beberapa entri dengan istilah sama diperbolehkan agar sumbernya tetap terpisah.

```sh
python tool/import_dictionary.py input.json assets/dictionary/offline.sqlite
python -m unittest discover -s test/native -p 'test_dictionary_import.py'
flutter test test/dictionary_test.dart
```

Alat impor memvalidasi data sebelum mengganti database. Database dimasukkan ke paket aplikasi; ketika aplikasi baru dimulai, salinan lokal diperbarui dari aset. Pencarian menggunakan awalan istilah, tanpa membedakan huruf besar/kecil, maksimal 100 hasil. `%` dan `_` diperlakukan sebagai karakter biasa.

Saat dibuka dari Alkitab, rujukan yang dikenali dapat ditekan untuk kembali ke kitab/pasal/ayat pertama pada rentang tersebut. Nama kitab mengikuti daftar kitab database Alkitab yang sedang digunakan.

Konten APK SABDA belum diimpor. Jika materi sumber memakai HTML, konversi perlu menangani paragraf, tabel, tautan istilah, serta rujukan ayat sebelum menghasilkan format teks dan references ini; jangan menyimpan HTML mentah sebagai teks definisi. Indeks SABDA yang bermasalah harus diverifikasi terhadap sumber sebelum diimpor.
