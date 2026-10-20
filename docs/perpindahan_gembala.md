# Hubungkan dan pindahkan gembala

## Persiapan satu kali

Publikasikan isi lengkap `firebase/firestore.rules` ke Firestore Rules proyek yang
sama dengan aplikasi. Perubahan ini menambahkan pembacaan daerah bagi akun
`role: admin` yang mempunyai identitas `isPastor: true`, dengan tetap memeriksa
tautan dua arah ke Data Jemaat dan daerah gereja. Penanda identitas hanya dapat
diubah superadmin. File ini tidak dipublikasikan otomatis oleh build APK/Windows.

## Hubungkan profil lama

1. Masuk sebagai superadmin, pilih gereja asal, buka Pengguna/Detail Pengguna.
2. Pilih **Hubungkan akun / profil gembala**.
3. Pilih Data Jemaat dan profil gembala yang benar. Tidak mencocokkan nama otomatis.
4. Konfirmasi. Akun menjadi admin gereja dengan identitas pelayanan gembala.

Jika gereja punya beberapa profil, pilih profil yang benar; profil lain tetap ada.
Jika belum ada profil sama sekali, profil dibuat dari Data Jemaat. Untuk menambah
profil berikutnya, tambahkan dahulu melalui bagian Gembala di halaman utama.
Profil terhubung tidak dapat dihapus melalui editor profil biasa.

## Pindahkan

1. Di detail akun tersebut pilih **Pindahkan Gembala dan Keluarga**.
2. Pilih gereja tujuan dan periksa nama seluruh keluarga pada ringkasan.
3. Konfirmasi penyimpanan.

Seluruh keluarga berdasarkan `idKepalaKeluarga` otomatis ikut. ID jemaat,
hubungan keluarga, biodata, foto dan UID akun tetap dipakai. Akun anggota keluarga
biasa tidak memperoleh admin. Semua akun gembala yang ikut keluarga tetap
menjadi admin di gereja tujuan, sementara penugasan admin daerah lama dicabut.
Profil gembala dipindahkan dengan ID yang sama; gembala lain tetap dipertahankan.
Akses daerah mengikuti daerah gereja tujuan. Data keuangan/inventaris/postingan
gereja asal tidak dipindahkan. Catatan Alkitab tetap di akun pemiliknya.

Buka kembali aplikasi gembala agar sesi mengambil gereja dan hak terbaru.
Riwayat berada di `churches/{gerejaAsal}/transfer_history/{idOperasi}`.
Riwayat menyimpan pelaksana, waktu, gereja asal/tujuan dan daftar jemaat/profil.

Seluruh perubahan disimpan dalam satu transaksi. Konflik ID tujuan, perubahan
susunan keluarga, tautan akun tidak cocok, profil belum ditautkan atau izin
superadmin berubah membatalkan transaksi. Maksimal 100 anggota per perpindahan.
Jika koneksi terputus saat simpan, muat ulang data sebelum mencoba lagi.
