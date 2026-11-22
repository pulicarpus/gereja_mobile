# Saldo Bulanan Otomatis — Uji Tampilan (read-only)

Branch: `feat/finance-auto-carry-display` (diturunkan dari `fix/finance-carryforward-preview` @ `0eebdb26893898edb2ca0ee0788f443dc5479041`).

Pratinjau saldo berjalan kini otomatis dihitung setelah laporan keuangan gereja dibuka/berganti tahun. Detail bulanan menampilkan:

- Saldo Awal (Otomatis) = saldo akhir bulan sebelumnya.
- Pemasukan baru (tanpa entri saldo awal manual berformat "Saldo Awal <NamaBulan>").
- Pengeluaran sebenarnya.
- Surplus/Defisit bulan ini.
- Saldo Akhir (Otomatis) = Saldo Awal + Pemasukan - Pengeluaran.

Saldo negatif tetap bertanda negatif dan perlu direkonsiliasi. Di bawah detail bulan ditampilkan status pencatatan saldo manual bila ada.

**Tidak ada pembuatan transaksi otomatis**. Seluruh perhitungan menggunakan pembacaan Firestore saja dan tidak menghapus/menyunting entri lama. Laporan utama tahunan diberi label "transaksi lama" agar tidak disalahartikan sebagai saldo akhir.

Data harus direkonsiliasi dengan bendahara. Pengenalan entri manual memakai pola konservatif, bukan kata "surplus" generik; entri dengan penulisan lain perlu ditinjau dan ditandai secara eksplisit sebelum rilis. Laporan tahunan resmi dan grafik masih memakai hitungan lama pada branch uji.

Uji: buka menu Keuangan Gereja dan lihat September–November, coba tahun berganti, dan uji bulan defisit. Perhatikan warning saldo awal tak terverifikasi serta selisih pencatatan manual.

Tidak ada data transaksi asli yang di-commit ke repo.
