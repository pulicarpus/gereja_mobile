# Pindah akun gereja dan menetapkan Gembala Sidang

## Pindah akun (superadmin)

Buka gereja asal → Manajemen Pengguna → pilih akun → Atur / Pindah Gereja →
pilih gereja tujuan → baca konfirmasi → Simpan. Admin gereja biasa tidak dapat
memindahkan akun antar gereja, dan superadmin tidak bisa memindahkan akun
sendiri atau akun superadmin lainnya melalui menu ini.

Transaksi memeriksa ulang kewenangan, akun, pemilik tautan lama, dan keberadaan
gereja tujuan sebelum menulis. Tautan `uid` di buku induk lama dilepas; akun
mendapat churchId/churchName/daerah tujuan dan jemaatId kosong. Biodata, keluarga,
riwayat, serta dokumen jemaat di gereja asal tidak dipindahkan atau dihapus.
Penugasan admin daerah dan pengurus lokal dicabut. Akun admin/BPJ menjadi user;
akun gembala tetap gembala tetapi belum mendapat akses daerah sebelum tertaut
kembali. Tidak ada perubahan separuh transaksi jika validasi gagal.

Pengguna masuk ulang, lalu melalui Profil Saya menghubungkan Data Jemaat yang
sudah disiapkan di gereja tujuan. Akun gembala yang belum tertaut juga bisa
masuk ke Beranda dan menautkan lewat Profil Saya. Nomor WhatsApp harus unik di
gereja tujuan; tahun lahir diperlukan untuk verifikasi.

Jika tautan lama rusak (jemaat hilang, UID tidak sesuai), perpindahan ditolak
agar tidak melepas akun orang lain. Administrator perlu memeriksa data itu
terlebih dahulu. Timeout tidak menyatakan gagal pasti: muat ulang daftar,
periksa gereja akun, baru bertindak lagi. Daftar gereja tujuan tidak menampilkan
gereja akun saat ini.

## Menetapkan gembala

Pemilik akun terlebih dahulu masuk ke Profil Saya → HUBUNGKAN DATA JEMAAT →
masukkan nomor WhatsApp → CARI DATA SAYA → masukkan tahun lahir → VERIFIKASI &
HUBUNGKAN. Admin gereja atau superadmin kemudian membuka Manajemen Pengguna →
akun tersebut → Jadikan Gembala Sidang → Simpan.

Admin gereja hanya dapat menetapkan jemaat biasa di gerejanya dan mencabut
jabatan gembala di gerejanya. Admin tidak dapat mengubah akun admin lain atau
akun superadmin. Superadmin dapat menetapkan akun admin sebagai gembala;
hak admin gerejanya diganti oleh role gembala. Role sendiri tidak dapat diubah.

Saat menyimpan, tautan dua arah ke buku induk diperiksa serta gereja dan daerah
harus tersedia. Penetapan gembala tidak membuat penugasan admin daerah baru.
Jika sudah memiliki penugasan admin daerah, penugasan terpisah itu tetap berlaku
sampai superadmin mencabutnya. Nama/foto pada Profil Gembala gereja tetap data
tampilan, tidak otomatis diubah melalui penetapan hak akun ini.

Pengguna masuk ulang atau memuat ulang sesi. Gembala tertaut dapat melihat data
daerah gerejanya dan ikut diskusi info/surat, tanpa mengedit data administrasi
kecuali juga memiliki penugasan admin daerah. Menu Turunkan ke Jemaat Biasa
mencabut role gembala tanpa menghapus tautan atau biodata.

Perubahan ini memakai izin admin/superadmin pada Rules yang sebelumnya sudah
disiapkan. Tidak membutuhkan koleksi atau rules baru. Pemeriksaan lokal/CI
memverifikasi kebijakan perpindahan, perlindungan pemilik tautan, dan alur tombol
penetapan gembala; akun produksi tidak dipindahkan dalam pengujian.
