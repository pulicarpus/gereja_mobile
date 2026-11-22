# Implementasi Uji: Laporan Bulanan Asli + Saldo Tahunan Berjalan

Branch `feat/finance-annual-closing-monthly-original` dari `feat/finance-auto-carry-display`, parent commit 9048ec0df3ad535138ca036305cc54ca041a2bee.

## Definisi
- **Pemasukan/pengeluaran bulanan:** hanya transaksi riil tanggal bulan itu; nominal saldo awal legacy dipisahkan dan tidak dimasukkan lagi.
- **Surplus/Defisit bulanan:** pemasukan bulan - pengeluaran bulan, **tanpa saldo bawaan**.
- **Saldo awal bulan:** saldo akhir bulan sebelumnya; bulan pertama didasarkan satu catatan saldo awal lama pada tanggal 1 (jika ada).
- **Saldo akhir bulan:** saldo awal + surplus/defisit bulan; negatif tetap bernilai negatif.
- **Laporan tahunan:** ambil saldo akhir bulan terakhir dari tahun yang dipilih, serta total pemasukan/pengeluaran **riil** selama tahun tersebut, saldo awal periode, dan surplus/defisit tahunan yang dipisahkan.
- **Lintas tahun:** saldo akhir Desember menjadi saldo awal Januari, tidak menjadi pemasukan baru.

## Batasan
Read-only; tidak ada `.set`, `.update`, `.delete` atau posting transaksi saldo otomatis. Riwayat Firebase tidak dihapus atau dimodifikasi. CSV yang diekspor dari layar daftar transaksi merupakan sumber data mentah, sehingga catatan saldo awal lama tetap tersedia di arsip. Perubahan ringkasan pada halaman Laporan Keuangan Gereja, bukan menghapus daftar transaksi maupun mengubah perhitungan lain di aplikasi.

**Penting:** saldo awal pembukuan pertama masih perlu diverifikasi oleh bendahara dan jumlah November mungkin belum lengkap. Jika saldo pembuka tidak dikenali atau ada selisih manual, aplikasi menampilkan peringatan. Pengujian memakai contoh fiktif atau angka ringkasan; **tidak mengunggah CSV jemaat ke GitHub**.
