# Sinkronisasi kitab dan pasal saat mengganti terjemahan

Branch `fix/bible-translation-same-chapter`, dari `fix/finance-clean-preview-pdf-totals` @ `28f1ce8b57219751fc78e913cef76ebdd73d69e2`.

## Perubahan
- Perpindahan **TB / TL / Mualang** mempertahankan `book_number` dan `chapter` yang sedang dibaca, **memulai tampilan pada ayat 1**. Tidak memulihkan posisi lama terpisah setiap terjemahan.
- Contoh: TB Matius 1:2 -> TL Matius 1:1 -> MUL Matios 1:1.
- Status kitab dan pasal dalam Mualang diperiksa dari berkas `MUALANG.SQLite3` yang terpasang (read-only) sebelum memindah terjemahan. Bila kitab/pasal tidak ditemukan, pesan tersedia dan aplikasi tetap pada terjemahan sebelumnya.
- Berlaku untuk PL, Ibrani dan Yudas yang tidak tersedia dalam Mualang saat ini; tidak memaksa pindah ke kitab Matius.
- Saat aplikasi dibuka ulang, posisi global terakhir diprioritaskan; posisi per-terjemahan lama hanya fallback kompatibilitas.
- Tidak mengubah isi Alkitab, database, akun, stabilo, catatan, ataupun Firebase.

## Uji perangkat
1. Buka TB Matius 1:2, ganti TL: Matius 1:1; lalu ganti MUL: Matios 1:1.
2. Buka TL Yohanes 3, pilih TB lalu MUL: kitab/pasal sama, ayat 1.
3. Buka TB Kejadian, Ibrani, Yudas, pilih MUL: tampil peringatan dan tetap di TB.
4. Jika SQLite Mualang belum diimpor, tampilkan pesan impor tanpa kehilangan posisi baca.
5. Uji setelah menutup dan membuka aplikasi kembali, serta kembali dari Mualang ke TB.

## Batasan
Uji helper memakai data fiktif; pemeriksaan SQLite terpasang dan UI perlu diuji di perangkat Android. Tidak menyertakan berkas teks Mualang dalam repo publik.
