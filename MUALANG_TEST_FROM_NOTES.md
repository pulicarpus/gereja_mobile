# GKII Mobile · uji Perjanjian Baru Mualang

Branch: `feat/mualang-pb-from-notes-richtext`
Base commit: `ba054a89be653ad1f81b457d22bfc0420362f4b0` dari `feat/notes-richtext-foundation`.

## Perubahan
- Pilihan bahasa Mualang ditambahkan ke pemilih terjemahan yang sudah ada (TB/TL tetap).
- Data Mualang tidak di-commit ke repo dan tidak dikemas dalam APK; impor berkas `MUALANG.SQLite3` dari perangkat Android melalui menu Alkitab.
- SQLite Mualang diimpor ke storage privat dan dibaca offline.
- Stabilo Mualang dipisahkan dari TB/TL. Posisi membaca per terjemahan disimpan secara lokal.
- Navigasi mengikuti 25 kitab PB yang tersedia; Ibrani dan Yudas belum ada.
- Audio hanya untuk TB; audio bahasa Mualang belum tersedia.

## Uji di Android
1. Download file `MUALANG.SQLite3` secara privat dan simpan di folder Download.
2. Unduh APK hasil workflow **Flutter Build APK** pada branch ini (artifact `app-release-zip`).
3. Instal APK uji setelah mencadangkan data lokal GKII Mobile.
4. Buka GKII Mobile → Alkitab → menu → **Impor Alkitab Mualang** dan pilih file SQLite.
5. Pada selector terjemahan pilih **MUL**. Uji Matios 1:1, Yohanes 3:16, Wahyu 22:21.
6. Uji navigasi, pencarian, mode pesawat, stabilo, dan peralihan TB/TL/MUL.

## Persyaratan sebelum distribusi
Teks Mualang masih membutuhkan verifikasi kualitas tampilan, ejaan, catatan kaki, judul perikop, dan izin distribusi ulang sesuai arahan Kartidaya. Jangan merge ke master sebelum build dan pengujian perangkat lulus.
