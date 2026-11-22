# Pratinjau Saldo Berjalan Gereja

Basis: feat/mualang-pb-from-notes-richtext @ b31af714e353433a1fdb98d87df98302d770a568.

## Tujuan

Pratinjau saldo berjalan **read-only**, tanpa mengubah laporan resmi, transaksi Firestore, atau pengelompokan asli. Gunakan untuk membandingkan penerimaan/pengeluaran riil dengan entri manual "Saldo Awal <bulan>" pada periode sebelumnya.

## Perhitungan

- Entri manual *Saldo Awal NamaBulan* tidak dianggap penerimaan baru.
- Saldo pertama ditentukan dari satu entri saldo awal bertanggal 1 pada bulan transaksi paling awal yang ditemukan sejak 2020. Jika tak ada, tampilkan peringatan; asumsi nol **bukan** saldo tervalidasi.
- Per bulan: surplus/defisit = penerimaan baru - pengeluaran; saldo akhir = saldo awal + surplus/defisit.
- Saldo akhir menjadi saldo awal bulan berikutnya termasuk lintas tahun.
- Selisih dengan saldo awal manual ditampilkan, tidak otomatis dibetulkan.
- Perpuluhan tetap dihitung sesuai model sumber keuangan umum yang telah ada.
- Kategori keuangan gereja tidak bercampur dengan kategori lain.
- Tidak ada tulisan database; hanya Firestore `.get()` dan dialog pratinjau.

## Uji

Pada halaman Laporan Keuangan Gereja tekan **Pratinjau Saldo Berjalan (Read-only)**. Pastikan hasilnya cocok dengan buku kas dan rekening, termasuk selisih Rp0 pada saldo bawaan. Perlakukan pratinjau sebagai hasil audit, bukan laporan resmi, sampai bendahara memverifikasinya.

File CSV/data transaksi gereja **tidak disertakan** pada GitHub. Pengujian otomatis menggunakan angka fiktif.
