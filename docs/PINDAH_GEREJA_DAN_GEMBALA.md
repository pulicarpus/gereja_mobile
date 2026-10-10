# Pindah akun gereja dan menetapkan Gembala Sidang

## Pindah akun (superadmin)

Buka gereja asal → Manajemen Pengguna → pilih akun → Atur / Pindah Gereja →
pilih gereja tujuan → baca konfirmasi → Simpan. Admin gereja biasa tidak dapat
memindahkan akun antar gereja, dan superadmin tidak bisa memindahkan akun
sendiri atau akun superadmin lainnya melalui menu ini.

Setelah memilih gereja tujuan, pilih **Pindahkan satu orang** atau
**Pindahkan satu keluarga**, kemudian baca konfirmasi dan Simpan.

Biodata lengkap (termasuk kolom tambahan, foto, dan riwayat pada dokumen jemaat)
dipindahkan ke koleksi jemaat gereja tujuan dengan ID yang sama. Dokumen di
gereja lama dihapus dalam transaksi yang sama. Akun yang tertaut tetap memiliki
jemaatId dan UID yang sesuai, sehingga cukup masuk ulang tanpa menautkan ulang.
Foto tetap menggunakan URL yang sama; berkas foto tidak diunggah ulang.
Akun tanpa tautan jemaat hanya dipindahkan akunnya; pilihan keluarga memerlukan
tautan jemaat yang valid.

Satu keluarga mencakup kepala keluarga dan semua dokumen yang merujuk kepala
keluarga itu, termasuk anggota tanpa akun. Akun anggota yang sudah tertaut ikut
berpindah. Hubungan keluarga dan kategorial jemaat tetap sama. Penugasan admin
daerah dan pengurus lokal dicabut untuk semua akun yang dipindahkan; admin
menjadi user, sementara gembala tetap gembala dan mengikuti daerah tujuan.
Jika salah satu akun merupakan superadmin, akun pelaksana, tautannya rusak,
atau ID jemaat sudah ada di tujuan, seluruh perpindahan ditolak tanpa perubahan.
Keluarga di atas 100 orang tidak dipindahkan otomatis.

Satu orang menjadi kepala keluarga sendiri di tujuan; keluarganya tidak ikut
berpindah. Kepala keluarga yang masih memiliki anggota tidak dapat dipindahkan
sendirian: pilih satu keluarga atau atur kepala keluarga pengganti terlebih
dahulu melalui menu keluarga. Perubahan susunan keluarga dari aplikasi diperiksa
melalui familyRevision supaya anggota yang baru ditambahkan tidak tertinggal.
Gunakan versi aplikasi terbaru untuk pengelolaan keluarga bersamaan dengan
perpindahan; perubahan manual lewat Console tidak mengikuti pemeriksaan ini.

Jika tautan lama rusak (jemaat hilang, UID tidak sesuai), perpindahan ditolak
agar tidak memindahkan data orang lain. Administrator perlu memeriksa data itu
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
