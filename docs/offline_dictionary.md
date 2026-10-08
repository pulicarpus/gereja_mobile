# Kamus offline SABDA — versi percobaan

Menu Alkitab → Kamus Alkitab membuka database SABDA bawaan tanpa internet atau konfigurasi tambahan. Paket menyertakan 18.386 entri dari APK Kamus Alkitab 2.0.1 yang diberikan pengguna, untuk percobaan di aplikasi gereja. Pencarian AI tetap tersedia lewat ikon bintang dan membutuhkan internet.

Sumber SABDA serta label sumber bagian ditampilkan pada definisi. HTML dikonversi menjadi teks dengan judul bagian; tautan istilah/Strong belum menjadi tombol. Rujukan ayat yang dikenali dipetakan ke database TB dan divalidasi sebelum dijadikan tautan. Rujukan yang tidak dikenali tetap tertulis dalam definisi. Tiga entri dengan offset rusak dilewati: Abadon, Apolion; Abagta; Abana. Versi ini menyertakan 71.905 rujukan yang tervalidasi.

Database terpaket: assets/dictionary/offline.sqlite. Data contoh sample.json digunakan untuk tes terisolasi. Tes tambahan memeriksa isi SABDA yang benar-benar dikemas.

## Mengulang konversi

```sh
python tool/import_sabda_development.py /path/to/extracted/assets/dictdata /path/to/output.sqlite --bible assets/TB.SQLite3
python -m unittest discover -s test/native -p 'test_*.py'
flutter test test/dictionary_test.dart
```

Konverter menghasilkan SQLite dan laporan .report.json, termasuk entri rusak, rujukan yang belum dikenali, dan nomor ayat yang tidak valid. Format sederhana milik aplikasi juga dapat diimpor menggunakan tool/import_dictionary.py dengan JSON berisi term, definition, source, references.

DICTIONARY_PATH tetap tersedia sebagai override pengembangan; tanpa parameter ini aplikasi langsung memakai kamus SABDA bawaan. Materi menggunakan teks biasa; transliterasi yang aslinya memakai font OLB khusus belum direkonstruksi dengan font tersebut.
