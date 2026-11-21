# Uji Alkitab Mualang di GKII Mobile

Branch khusus: `feat/mualang-pb-import-test` (tidak mengubah `master`).

## Alur uji di Android

1. Unduh berkas `MUALANG.SQLite3` dari paket yang disediakan secara privat; simpan di Download perangkat.
2. Unduh APK hasil GitHub Actions branch ini (workflow **Flutter Build APK** → artifact **app-release**), ekstrak ZIP artifact, lalu instal APK.
3. Buka GKII Mobile → Alkitab → menu (⋮) → **Impor Database Mualang**.
4. Pilih `MUALANG.SQLite3` dari Download; APK memeriksa struktur dan mengimpor ke penyimpanan privat Android.
5. Pilih **Versi: Mualang (PB)**. Coba Matios 1:1, Yohanes 3:16, Wahyu 22:21.
6. Pilih **Versi: Terjemahan Baru (TB)** untuk kembali; tes navigasi, pencarian, stabilo, dan mode offline.

**Penting:** database teks PB Mualang TIDAK disertakan/di-commit di repo publik. Harap dapatkan file dari pembicaraan privat dan pastikan izin Kartidaya sebelum mendistribusikan terjemahan. Build GitHub Actions hanya menyertakan kode fungsi impor. Ibrani dan Yudas belum tersedia. Catatan pribadi lintas versi belum dipisahkan, dan audio Mualang belum tersedia; penggunaan saat ini untuk uji internal.

## Status pengujian

Fitur impor dan selector dikodekan, tetapi perlu hasil Flutter build GitHub Actions dan QA di Android. Jangan merge ke master sebelum semuanya lulus.