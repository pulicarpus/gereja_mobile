# Catatan Pengembangan — perbaikan-fitur-daerah

Tanggal: 2 Oktober 2026
Baseline: `fitur-daerah`
Branch kerja: `perbaikan-fitur-daerah`

## Aturan kompatibilitas
- Jangan merge ke `fitur-daerah` sebelum APK diuji.
- Jangan migrasi, menghapus, atau mengganti arti/nama field Firebase yang dipakai aplikasi lama.
- Perubahan baru harus membaca data lama dengan fallback.
- Jangan mengubah Firestore/Storage production rules atau data production dalam fase ini.
- Aplikasi lama yang sudah terpasang harus tetap dapat membaca struktur Firebase yang sama.

## Fase 1 — Stabilitas (selesai)
- Refresh profil/role dari Firestore saat login, splash, dan home dengan cache lokal sebagai fallback offline.
- Blokir akun `isBlocked=true` pada login/startup.
- Pisahkan konteks `userDaerah` dan `adminDaerahArea` di cache lokal.
- Perbaiki Admin Daerah yang kehilangan `adminDaerahArea` setelah login.
- Gembala/BPJ memakai daerah user untuk Pusat Daerah.
- Listener church realtime disimpan/dibatalkan dengan benar.
- Reset state saat pindah konteks gereja agar data gereja lama tidak tertinggal.
- Pertahankan Mode Pantau Superadmin setelah refresh session.
- Hapus fallback rekening contoh; tampilkan empty state bila rekening belum tersedia.
- Tampilkan warning + retry jika refresh profil gagal.
- APK release Fase 1 berhasil dibuild.

## Fase 2 — Ketepatan data
- Parser ulang tahun kompatibel dengan DD/MM/YYYY, DD-MM-YYYY, YYYY-MM-DD, DD/MM/YY, dan Firestore Timestamp.
- Urutan ulang tahun: hari/tanggal yang akan datang di bulan berjalan didahulukan, lalu yang sudah lewat.
- Tidak ada migrasi tanggal lahir di Firebase.
- Logout tidak lagi `SharedPreferences.clear()`; hanya key session yang dihapus sehingga cache fitur lain tidak ikut hilang.

## Fase 3 — UX halaman utama
- Quick Access sempat diuji lalu dibatalkan dan dihapus berdasarkan hasil uji pengguna.
- Ayat home tidak lagi berubah akibat ketukan tidak sengaja; diperlakukan sebagai Ayat Hari Ini selama sesi/hari.
- Empty state rekening tetap aman.

## Fase 4 — Pusat Daerah / role
- Superadmin tetap memiliki kewenangan penuh; Mode Pantau bukan pembatasan read-only.
- Admin Daerah memakai `adminDaerahArea`; Gembala/BPJ dapat fallback ke `userDaerah`.
- Tidak ada perubahan field Firebase atau migrasi daerah.

## Fase 5 — Informasi Home + kompatibilitas (selesai implementasi)
- Quick Access dibatalkan/dihapus berdasarkan hasil uji pengguna.
- Home membaca pengumuman lama dari `churches/{churchId}/pengumuman/utama`; tidak membuat collection/field baru.
- Pengumuman Home memiliki indikator BARU/unread yang disimpan lokal di SharedPreferences, bukan Firebase.
- Teks pengumuman terakhir dicache lokal sebagai fallback ketika snapshot online tidak tersedia.
- Home membaca agenda terdekat dari collection `jadwal` dan field `tanggal` yang sudah ada.
- Kartu ulang tahun hari ini dapat membuka ucapan WhatsApp menggunakan field lama `nomorTelepon`; tidak menulis ke data jemaat.
- Mute chat berlaku untuk semua tipe pesan (teks, gambar, dokumen, audio), bukan teks saja.
- Perubahan yang membutuhkan backend/schema baru sengaja ditunda agar kompatibilitas aplikasi lama terjaga.

## Temuan penting yang masih harus ditangani setelah APK diuji
1. OneSignal REST key dan Telegram bot token masih berpotensi berada di client APK; idealnya pengiriman push/media server-side.
2. Firestore/Storage Security Rules tidak ada di repo sehingga keamanan server-side belum dapat diverifikasi dari source.
3. Claim/sinkronisasi jemaat dengan nomor telepon + tahun lahir perlu diperkuat server-side.
4. Role/privilege write dari client harus dijamin oleh Security Rules.
5. Kode undangan gereja perlu uniqueness yang lebih kuat tanpa memutus kode lama.
6. Unread pengumuman saat ini bersifat per-perangkat (SharedPreferences). Sinkronisasi lintas perangkat baru boleh dipertimbangkan setelah strategi backend kompatibel disepakati.
7. Perlu audit UI di perangkat kecil/besar dan akun semua role setelah APK final.

## Checklist uji APK
- Jemaat: login, home, Quick Access, ulang tahun, rekening, drawer.
- Gembala/BPJ: Pusat Daerah mengarah ke daerah user.
- Admin gereja: edit foto/gembala/rekening dan Data Jemaat.
- Admin Daerah: Pusat Daerah dan hak edit daerah.
- Superadmin: daftar daerah, pilih gereja, Mode Pantau, kembali ke gereja asal.
- Akun blocked: tidak boleh masuk home.
- Offline/lambat: cache session tetap membuka app dan warning retry tampil.
- Chat muted: teks/gambar/dokumen/audio semuanya ditolak.
- Logout/login ulang: cache non-session tidak ikut terhapus.

## Target setelah APK final
1. Audit hasil APK bersama pengguna dari screenshot/hasil uji nyata.
2. Perbaiki regresi yang ditemukan tanpa merge ke branch produksi.
3. Audit Firebase Security Rules secara terpisah (tanpa deploy langsung).
4. Rancang backend aman untuk OneSignal/Telegram secrets.
5. Setelah disetujui dan diuji, baru tentukan strategi merge/release.


## Pematangan Aset Gereja + Pokok Doa
- Aset: query tidak lagi bergantung pada `createdAt` untuk sorting sehingga data legacy tanpa field tersebut tetap dapat tampil.
- Aset: tambah/edit memakai validasi trim dan jumlah > 0, foto dikompresi saat dipilih, upload baru di-rollback bila save Firestore gagal, dan foto lama dibersihkan setelah update sukses.
- Aset: delete memiliki guard permission di action layer dan melaporkan jika cleanup file foto gagal.
- Aset: dashboard lokal Total Unit/Baik/Rusak, filter kondisi, pencarian, dan preview foto fullscreen; tidak menambah field Firebase baru.
- Doa: Gembala ikut dapat melihat doa privat di UI sesuai keterangan fitur; owner/admin tetap mengelola delete sesuai perilaku lama.
- Doa privat tidak lagi mengirim notifikasi publik ke seluruh gereja.
- Doa: edit diverifikasi lagi berdasarkan UID pemilik + konteks gereja, owner tidak bisa meng-Amin-kan doanya sendiri, parsing data legacy dibuat toleran, sorting dilakukan lokal, ditambah search/filter.
- Format lama `daftarAmin` berbasis nama dipertahankan untuk kompatibilitas aplikasi lama; kelemahan nama ganda belum dapat diselesaikan tanpa strategi schema kompatibel.
- Firestore Rules production TIDAK diubah/deploy dari branch ini.

## Audit Rules Firebase yang diberikan pengguna
- CRITICAL: `users/{uid}` mengizinkan user menulis seluruh dokumennya sendiri. Secara rules, user dapat mencoba mengubah `role` miliknya menjadi `admin`; ini dapat mengalahkan helper `isPrivilegedUser()`.
- CRITICAL: `churches/{churchId}` dan recursive `match /{allPaths=**}` memberi read/write ke semua user login. Rule khusus `jemaat`, `chats`, dan `aset` di bawahnya tidak membatasi akses karena allow Firestore bersifat OR.
- HIGH: `prayers/{prayerId}` saat ini read/write untuk semua user login, sehingga label Privat belum merupakan perlindungan server-side.
- HIGH: `keuangan_daerah`, `perpuluhan_daerah`, `info_surat_daerah`, dan beberapa modul global lain juga read/write untuk semua user login.
- Aset global `aset_gereja` write sudah dibatasi oleh `isPrivilegedUser()`, tetapi helper tersebut tetap terdampak celah privilege escalation pada dokumen user.
- Security Rules perlu diperketat sebagai pekerjaan terpisah dan diuji dengan Emulator/Rules Playground sebelum deploy agar aplikasi lama tidak putus.


## Pematangan Ruang Chat
- Chat memakai `getChurchIdForCurrentView()` dan mempunyai guard akses di halaman, bukan hanya dari menu sebelumnya.
- Anggota kategorial yang sesuai dapat membuka Chat Group kategorial; hak moderasi tetap hanya admin/superadmin atau pengurus kategorial yang sesuai.
- Mute diperiksa untuk teks, gambar, dokumen, dan voice note; jika status mute tidak dapat diverifikasi, pengiriman diblokir sementara agar tidak fail-open.
- Edit pesan diverifikasi ulang berdasarkan UID pemilik dan hanya berlaku untuk pesan teks.
- Hapus pesan mempunyai konfirmasi, guard action-layer, verifikasi ulang pemilik/moderator, serta error handling.
- Voice note tidak lagi membuka dua recorder mikrofon sekaligus. Rekaman memakai satu AudioRecorder dan waveform playback dirender lokal tanpa PlayerController kosong per pesan.
- Lampiran dokumen dibatasi ke tipe dokumen umum dan maksimal 20 MB; tipe berbahaya seperti APK/EXE/script diblokir saat membuka.
- Download dokumen memakai nama file yang disanitasi, cache key berdasarkan URL, status HTTP/ukuran dicek, dan kegagalan OpenFile ditangani.
- Kamera pada input chat sekarang benar-benar membuka kamera; menu lampiran tetap membuka galeri.
- Pesan dibatasi 2.000 karakter, caption gambar 500 karakter, double-send ditekan dengan state pengiriman dan throttle singkat.
- Daftar chat memakai limit awal 100 pesan dengan tombol memuat riwayat lebih lama untuk mengurangi beban baca/render.
- Error/empty state chat dibuat eksplisit, data legacy untuk timestamp/waveform/file URL lebih toleran, dan ikon centang biru palsu (seolah read receipt) diganti indikator pesan tersimpan.
- Notifikasi chat kategorial ditargetkan berdasarkan `active_church` + tag OneSignal `kelompok`; login/home menjaga tag kelompok tetap sinkron.
- Sesi OneSignal dilepas ketika akun diblokir atau keluar dari alur validasi sehingga perangkat tidak terus menerima notifikasi akun lama.
- Info/Surat Daerah yang dibagikan ke chat memakai konteks gereja yang sedang aktif.
- Firestore Rules production tetap TIDAK diubah pada fase ini.

## Sisa Ruang Chat yang membutuhkan backend/Rules
- Telegram bot token dan OneSignal REST key masih berada di APK; keduanya harus dipindahkan ke backend/server dan token perlu dirotasi setelah migrasi.
- URL file Telegram lama masih mengandung bot token karena format ini diperlukan aplikasi lama; menghilangkannya secara kompatibel membutuhkan endpoint/proxy backend.
- Hapus pesan belum dapat menjamin penghapusan file eksternal Cloudinary/Telegram; cleanup media membutuhkan backend.
- Mute, kepemilikan pesan, identitas pengirim, akses chat kategorial, dan hak moderator baru benar-benar aman setelah Firestore Rules diperketat.


## Pematangan Renungan + Buku Lagu
- Renungan menyimpan tanggal cache bersama judul/isi sehingga renungan lama tidak lagi tampil seolah-olah milik hari ini.
- Cache lama tetap dipertahankan bila sinkronisasi gagal; hasil scraping baru hanya mengganti cache jika struktur artikel lolos validasi minimum.
- Status HTTP, timeout, error sinkronisasi, sumber konten, dan status TERSIMPAN/TERBARU ditampilkan lebih jujur.
- Ukuran font Renungan tersimpan lokal; tombol perbesar/perkecil ditambah tanpa mengubah data Firebase.
- Share Renungan dinonaktifkan sampai konten layak dibagikan dan memakai sumber yang sesuai URL yang benar-benar diambil aplikasi.
- Buku Lagu tidak lagi melakukan auto-write kategori saat halaman daftar dibuka. Data kategori kosong/HYMNE dibaca sebagai kelompok NKI secara lokal untuk kompatibilitas.
- Daftar lagu tahan data legacy, error state punya retry, pencarian mencakup judul/nomor/pencipta/lirik, sorting NKI numerik dan Kontemporer alfabetis.
- Hak tambah/edit/hapus dicek kembali pada action layer dengan perilaku admin yang sama seperti sebelumnya; Firestore Rules belum diubah.
- Editor lagu memvalidasi data, memeriksa duplikat juga saat edit, membatalkan simpan bila pemeriksaan duplikat gagal, dan mempertahankan nomor NKI apa adanya tanpa normalisasi 1/01/001.
- Respons Gemini diparsing defensif; hasil hanya mengisi form untuk ditinjau admin sebelum disimpan.
- Audio hanya muncul untuk lagu kelompok NKI/HYMNE, bukan karena sekadar memiliki nomor. Pause sekarang dapat dilanjutkan dengan resume tanpa memulai ulang.
- Ukuran font lirik lagu tersimpan lokal.
- Susunan Acara mencari lirik dari cache katalog lagu yang sudah dimuat dan mencocokkan judul secara normalisasi lokal sehingga tidak bergantung pada query exact-title baru.
- Tidak ada migrasi, rename field, atau perubahan Firestore Rules pada fase ini.
