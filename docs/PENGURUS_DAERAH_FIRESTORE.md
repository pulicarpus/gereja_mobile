# Akses Pengurus Daerah

Halaman memakai `struktur_pengurus_daerah/{idDaerah}` dan subkoleksi
`penasehat`, `mkdp`, `bpk`, serta `komisi`. ID daerah di aplikasi adalah
`Uri.encodeComponent(namaDaerah.trim())`.

`firebase/firestore.rules` menggabungkan aturan lengkap yang dikirim pengguna
pada 9 Oktober 2026 dengan tambahan untuk jalur tersebut. Izin modul lama
dipertahankan. File belum diterapkan ke Firebase produksi.

## Daerah dinamis

Tidak ada daftar nama daerah di Rules. Superadmin yang tidak diblokir dapat
membaca semua daerah, termasuk dokumen yang belum dibuat dan subkoleksi kosong.
Ini berlaku juga untuk nama dengan spasi seperti `Daerah Belitang`, nama daerah
baru, dan nama Unicode. Superadmin membuat dokumen utama dengan menyimpan
pengurus inti atau komisi pertama melalui aplikasi.

Inventaris memakai koleksi datar `inventaris_daerah`; daftar pengurus lama
memakai `pengurus_daerah`. Keduanya juga dicakup oleh file Rules ini:
superadmin dapat mengelola semua daerah, admin daerah hanya daerahnya.
Query admin wajib memakai filter `daerah` seperti dalam aplikasi. Admin bisa
membuat inventaris pertama tanpa dokumen induk pengurus. Pembacaan ID yang
belum ada diizinkan untuk transaksi pembuatan oleh admin daerah aktif;
pembacaan dokumen yang sudah ada tetap diperiksa berdasarkan daerahnya.
Pemindahan barang ke daerah lain lewat perubahan field `daerah` ditolak.

Setelah dokumen utama dibuat, admin dengan `users/{uid}.adminDaerahArea` sama
persis dengan `daerah` pada dokumen utama dapat membaca dan mengubah pengurus
serta komisi. Pembuatan dokumen utama pertama dibatasi ke superadmin agar admin
tidak dapat mengambil ID daerah lain. Admin tidak harus menunggu perubahan
Rules saat daerah baru ditambahkan; superadmin cukup mengisi pengurus awal.

Nama `daerah` pada induk tidak dapat dipindahkan melalui pembaruan. Data baru
pada subkoleksi harus menunjuk daerah yang sama dengan induk. Menghapus induk
melalui fitur pengurus tidak diizinkan agar subkoleksi tetap bertaut.

## Menerapkan

1. Buka `firebase/firestore.rules` di GitHub, klik Raw, dan salin seluruh isinya.
2. Buka Firebase Console → Firestore Database → Rules, tempel isi file, lalu Publish.
3. Pada aplikasi dengan akun superadmin, tekan Coba lagi di Pengurus Daerah.

Galat `permission-denied` membutuhkan perbaikan Rules di server; memasang APK
saja tidak mengubah Rules. Aturan foto Firebase Storage terpisah dan tidak
diubah oleh file ini. Tidak ada kebutuhan memasang APK baru untuk pembaruan
aturan ini.

## Pengujian lokal

Dengan Node.js 22+ dan Java 21+, jalankan `npm install` lalu `npm test` dari
folder `firebase`. Tes memakai proyek emulator `demo-gkii-pengurus` dan tidak
mengakses Firebase produksi. Tes meliputi daerah baru/nama berspasi/Unicode,
pembacaan dokumen belum ada dan subkoleksi kosong oleh superadmin, pembuatan
induk/komisi atomik, edit anggota oleh admin sendiri, penolakan akun daerah
lain/tanpa login/diblokir, dan izin modul lama yang diuji.
Tes inventaris mencakup transaksi pembuatan barang pertama, query daerah,
edit/hapus oleh admin daerah sendiri, penolakan query tanpa filter dan akses
daerah lain, serta metadata URL foto (izin upload Storage tetap terpisah).
