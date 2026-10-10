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

## Gembala tertaut: hanya lihat

Gembala dapat membaca pengurus, inventaris, kas, perpuluhan, dan info/surat
milik daerah gerejanya. Rules memeriksa role `gembala`, akun aktif, `churchId`,
`jemaatId`, keberadaan gereja/jemaat, dan `jemaat.uid` sama dengan UID akun.
Daerah diperoleh dari dokumen gereja; field daerah akun yang lama tidak menjadi
sumber izin. Aplikasi menyegarkan daerah ini saat login dan penyegaran sesi.

Tombol tambah/edit/hapus keuangan disembunyikan dari gembala, dan semua penulisan
koleksi daerah tersebut tetap ditolak server kecuali akun juga ditugaskan
sebagai admin daerah atau superadmin. Gembala tidak bisa mengubah role,
penugasan admin daerah, atau status blokir sendiri lewat profil. Pengeditan
profil biasa dan alur penautan jemaat tetap memakai izin yang ada.

Daerah di dokumen struktur pengurus perlu diinisialisasi superadmin terlebih
dahulu. Pengaturan Daerah masih merupakan menu placeholder yang sudah ada;
perubahan ini tidak membuat fungsi pengaturan baru. Data Gereja & Pengerja
serta Dashboard memakai halaman baca yang sudah tersedia.

Tes emulator juga mencakup gembala tertaut dengan daerah akun yang kedaluwarsa,
query daerah sendiri, larangan tambah/edit/hapus, akun belum tertaut/tautan
hilang/UID jemaat tidak cocok/diblokir, dan larangan meningkatkan izin sendiri.

## Diskusi info dan surat

Setiap postingan memiliki subkoleksi `info_surat_daerah/{postId}/komentar`.
Tombol Diskusi & pertanyaan membuka percakapan real-time per postingan.
Semua akun yang diizinkan membaca postingan dapat mengirim teks maksimal
2.000 karakter, termasuk gembala tertaut yang tetap tidak bisa mengedit
postingan utama. Penulis boleh menghapus komentarnya sendiri; superadmin dan
admin daerah yang sesuai dapat memoderasi komentar. Komentar tidak diedit.

Rules memeriksa izin melalui postingan induk, UID penulis, schema pesan,
panjang teks, dan timestamp server. Penghapusan postingan menutup akses
komentar; dokumen komentar tersimpan tidak ikut dihapus otomatis. Tidak ada
perubahan aturan upload Storage karena komentar berupa teks.

Pengiriman menggunakan ID dokumen tetap dan transaksi. Jika timeout tidak
memastikan hasil, draft dikunci dan kirim ulang memeriksa ID yang sama, sehingga
tidak membuat pesan ganda. Halaman memuat 100 komentar terbaru terlebih dahulu,
dengan tombol memuat komentar sebelumnya. Pembacaan serta penulisan komentar
ke postingan yang hilang/daerah lain ditolak. Tes emulator juga memeriksa
pemalsuan UID, pesan kosong/terlalu panjang, timestamp palsu, field tambahan,
larangan edit komentar, dan moderasi oleh admin.

## Pengumuman dari daerah yang dahulu duplikat

Info & Surat untuk superadmin dan gembala membaca variasi field `daerah`
yang hanya berbeda huruf besar/kecil atau spasi pada data gereja. Komentar
tetap disimpan di postingan asal; tidak ada penyalinan atau penghapusan data.
Rules menyamakan variasi tersebut saat memeriksa akses baca gembala tertaut.
Hak menulis pengumuman dan hak admin daerah tetap memakai identitas persis.

Perbaikan ini memerlukan aplikasi terbaru **dan** Publish seluruh file
`firebase/firestore.rules` terbaru mengikuti langkah Menerapkan di atas.
APK sendiri tidak memperbarui Rules produksi.

Pengurus Daerah untuk gembala mencari dokumen induk yang sudah ada di antara
variasi nama daerah tersebut. Nama daerah tidak langsung dipakai untuk membuka
jalur kosong yang berbeda kapitalisasinya. ID dokumen yang ditemukan dipakai
juga saat membuka anggota komisi. Query induk diizinkan hanya bila semua daerah
yang dicari dapat dibaca akun; hak edit gembala tetap ditolak. Pembaruan ini
memerlukan Publish Rules terbaru dan aplikasi terbaru.
