# GKII Mobile: Saldo Pembuka & Ekspor Laporan Keuangan Lengkap

## Fitur

Pada halaman **Laporan Keuangan Gereja** tersedia:

1. **Ekspor Laporan Lengkap (PDF / CSV)**. Pilihan: satu bulan yang dipilih di dropdown, seluruh bulan tahun terpilih masing-masing dirinci, atau satu laporan gabungan setahun.
2. **Atur Saldo Pembuka (Gereja Baru)**, hanya admin dan hanya ketika saldo pembuka pertama belum ditemukan. Pilih bulan/tahun pada halaman, masukkan kas/rekening sebenarnya pada awal periode, lalu simpan.
3. Rincian pemasukan, pengeluaran, surplus/defisit, dan saldo awal/akhir tetap dihitung dengan saldo berjalan tanpa mencatat saldo bawaan sebagai pemasukan baru.

## Kaidah akuntansi dan keamanan

- **Pemasukan umum** hanya transaksi operasional `jenis=Pemasukan` yang bukan saldo bawaan.
- **Perpuluhan** dibaca dari koleksi `perpuluhan` secara terpisah; tabel berdasarkan penyetor (`jemaatId` atau nama jika tidak ada), dengan jumlah setoran dan total masing-masing.
- **Total pemasukan = pemasukan umum + perpuluhan**. Tidak menghitung perpuluhan dua kali.
- **Pengeluaran** hanya transaksi `jenis=Pengeluaran` yang valid.
- **Saldo akhir = saldo awal + total pemasukan - total pengeluaran**, termasuk carry-forward lintas bulan/tahun.
- Saldo pembuka **bukan** pemasukan/ pengeluaran. Untuk gereja baru disimpan dalam koleksi `transaksi` sebagai `jenis=Saldo Pembuka`, `saldoPembuka=true`, tanggal 1 bulan pembukuan, dengan ID deterministik per kategori. Helper saldo berjalan mengecualikannya dari pendapatan dan belanja.
- Data historis lama tidak dihapus. Catatan `Saldo Awal <nama bulan>` pada transaksi lama tetap dicatat sebagai arsip, tidak dihitung ulang sebagai pendapatan.
- Pengaturan saldo pembuka memerlukan admin, otorisasi server `ChurchWriteAccess`, pemeriksaan periode sebelumnya, dan penulisan Firestore transaction untuk mencegah duplikasi. Tidak ada data yang disimpan hanya dengan membuka laporan.
- Jika server Firestore membatasi jenis transaksi, penyimpanan saldo pembuka akan gagal dengan pesan; jangan mengubah rules produksi tanpa audit keamanan.
- **PDF/CSV menyertakan nama penyetor perpuluhan. Simpan dan bagikan hanya kepada pihak gereja yang berwenang**.
- Untuk opsi seluruh bulan, rincian pemasukan/pengeluaran dikelompokkan bulanan dan **satu tabel rekap perpuluhan per penyetor** disajikan pada bagian akhir.
- Untuk opsi satu tahun, semua transaksi pemasukan/pengeluaran dan satu tabel perpuluhan tahunan digabung dalam satu laporan.
- Jika pembukuan baru dimulai di pertengahan tahun, periode rekap dimulai bulan pertama yang mempunyai data, bukan otomatis menganggap Januari sebagai awal pembukuan.
- Periksa fisik kas/rekening dan kelengkapan data, terutama bila muncul peringatan saldo pembuka atau selisih catatan manual.

## Langkah uji

1. Uji APK di branch ini pada gereja dengan saldo manual Agustus–November: pastikan saldo Agustus 10.839.000, September 10.632.000, Oktober 12.174.000, November 15.641.000 **jika data tetap sama**.
2. Ekspor PDF dan CSV satu bulan, semua bulan, dan tahunan. Periksa total perpuluhan per nama dan total pemasukan.
3. Uji gereja contoh yang benar-benar baru: input saldo pembuka sekali, lalu input transaksi pertama. Pastikan penolakan saldo pembuka kedua; jangan uji tulis pada kas produksi tanpa otorisasi.
4. Uji user non-admin: tombol atur saldo pembuka tidak boleh muncul.
5. Lakukan peninjauan manual terhadap hasil ekspor sebelum dipakai untuk laporan resmi.

## Batasan

Perubahan ada di branch fitur, bukan master. Data nyata jemaat **tidak di-commit**. Pengujian otomatis memakai nilai fiktif. Export PDF/CSV dibuat dari pembacaan Firestore; fitur tidak menulis transaksi kecuali admin secara eksplisit menyimpan saldo pembuka baru.
