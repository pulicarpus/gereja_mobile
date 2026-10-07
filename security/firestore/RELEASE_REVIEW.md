# Penyesuaian aplikasi dan backend — paket review, tanpa deploy

Source dasar Android `1272a970f585d63edda8ecbf34b5b1df98ebf85b`; seluruh perubahan
di `security/firestore-compatibility`. Cabang Android utama dan Windows tidak
diubah. Tidak ada aturan, IAM, Functions, indeks, data, token URL, atau file
Firebase produksi diubah. Pengujian memakai proyek demo dan fixture sintetis.

## Perubahan yang siap diuji

- PrayerFeed memilih query publik `churchId + isPrivat=false` dan query doa milik
  sendiri `churchId + uid`. Hasil digabung/dedup tanpa mengunduh doa privat akun
  lain. Admin/Gembala gereja terkait dan superadmin memperoleh query gereja penuh
  berdasarkan snapshot akun terbaru dari server, bukan cache UserManager.
  Pergantian akun/role/blokir membatalkan subscription dan mengosongkan hasil.
- Doa lama tanpa flag isPrivat tetap terlihat oleh pemilik/moderator. Aplikasi
  anggota biasa tidak dapat mengambil query missing field secara aman tanpa
  strategi migrasi. Banner menjelaskan data lama perlu pemeriksaan admin; tidak
  ada backfill otomatis atau penghapusan doa. Admin dapat memeriksa; pemilik dapat
  menyimpan flag publik secara eksplisit melalui editor yang sudah ada.
- Seluruh uploader Firebase (profil, jemaat, aset, header/gembala, pengurus,
  lampiran daerah) memeriksa batas ukuran dan signature awal file, kemudian
  mengirim metadata MIME eksplisit. MIME gambar mengikuti bytes meski nama.jpg.
  Extension lampiran dinormalisasi lowercase. Foto <=10 MiB, lampiran <=20 MiB.
  Pemeriksaan signature sederhana bukan decoder atau pemindai malware.
- Join gereja dan link jemaat menjadi permohonan server lalu **persetujuan admin**.
  Identitas bukan dibuktikan oleh pengetahuan nomor/tahun lahir saja. Admin harus
  memeriksa pemohon di luar aplikasi; tombol konfirmasi menyatakan kewajiban ini.
  Admin membuka daftar permohonan lewat ikon persetujuan di Manajemen Pengguna.
- Backend `functions/` memiliki callable searchJemaatCandidate,
  requestJemaatLink, requestChurchMembership dan reviewProfileRequest. UID berasal
  dari Auth; role/church/block diambil fresh dalam transaksi saat review. Profil
  tetap memakai users dan churches/{id}/jemaat, tidak dipindah ke skema baru.
- Permohonan menulis koleksi tambahan `profile_requests`, dan pembatasan 10
  percobaan per 15 menit menulis `profile_rate_limits`, **hanya saat backend nanti
  diaktifkan**. Client tidak boleh menulis keduanya. Tidak ada koleksi tersebut
  dibuat di produksi oleh pekerjaan ini. Tidak ada notifikasi eksternal otomatis.
- Request ID stabil per UID/kind, pending retry idempotent, request berbeda tidak
  menimpa pending, review atomik/idempotent, request berumur >7 hari tidak dapat
  disetujui. Book revision diperiksa agar admin tidak menyetujui biodata yang
  berubah sejak pengajuan. Dua approval bersamaan tidak dapat mengambil satu buku.
- Baru dibuat `firestore.release.rules` dan `storage.release.rules` untuk versi
  baru. Self join/link langsung ditolak; create users harus belum bergereja;
  doa privat dibatasi pemilik/moderator. Kandidat compat tetap disimpan sebagai
  pembanding transisi, **bukan pengganti kandidat release**.

## APK yang dibangun

APK cabang audit adalah **preview untuk review**, bukan rollout massal. Halaman
utama/profil akun existing tetap memakai Firebase yang sudah dikonfigurasi.
Backend baru BELUM di-deploy: pendaftaran/tautan baru akan memberi pesan layanan
belum aktif, bukan fallback ke write client yang tidak aman. Aplikasi/rules baru
tidak boleh diaktifkan terpisah tanpa uji staging. Tes build tidak mengeksekusi
request ke data Firebase produksi. Rahasia notifikasi lama di APK belum dipindah
ke server oleh perubahan ini; ini batasan keamanan terpisah yang tetap ada.

## Pengujian

1. CI menjalankan tes Firestore/Storage kompatibilitas terdahulu.
2. Tes release memakai Firestore + Storage + Auth + Functions lokal. HTTP callable
   sungguhan diuji dengan token Auth emulator: anonymous/blocked ditolak, payload
   UID diabaikan, crosschurch review ditolak, phone/tanggal lama, approval/join,
   revoked roles, stale book dan race dua pemilik. Data fixture dibersihkan hanya
   di emulator, tidak ada credential/proyek produksi.
3. Flutter analyze, seluruh regression test dan build release APK di GitHub.
   Penambahan tes mencakup ukuran/MIME/header, moderator dan UI pengajuan pending.
4. Emulator tidak membuktikan IAM/billing/index produksi, semua APK historis,
   provider perangkat/scanner, decode file penuh, ataupun pemeriksaan identitas
   manusia. Rilis tetap memerlukan staging dan uji perangkat.

## Yang masih harus ditinjau sebelum aktivasi

- Kandidat release membatasi query doa/join/link yang digunakan APK lama.
  Tidak mungkin sekaligus menolak write client yang sama dan mengizinkan APK lama
  yang mengirim write tersebut. Siapkan distribusi APK baru dan jadwal transisi;
  jangan mengklaim bisa mengaktifkan tanpa dampak pada semua APK lama.
- Backend draft menggunakan us-central1; pilih lokasi sesuai database dan
  koordinasikan region client-server sebelum deploy. Jangan mengganti region
  sepihak setelah aplikasi beredar. Cloud Functions production mungkin membutuhkan
  pengaturan billing/permissions; pekerjaan ini tidak mengaktifkannya.
- `firestore.release.indexes.json` menyediakan indeks query baru. Gabungkan ke
  konfigurasi indeks existing jika diperlukan; jangan mengganti seluruh indeks
  produksi dengan file ini. Emulator tidak memverifikasi indeks produksi.
- Privasi URL download bertoken tetap perlu kebijakan terpisah; token/file lama
  tidak dicabut. Baca SDK Storage kandidat masih luas untuk kompatibilitas.
- Kamus kontribusi pertama dan integritas pasangan kas/perpuluhan daerah belum
  memperoleh moderasi/invariant backend penuh. Rules release tidak diklaim
  menyelesaikan semua risiko tersebut. Review akun dengan role lama terlanjur
  berbahaya juga belum dilakukan dan tidak dapat diperbaiki hanya lewat kode.
- Siapkan retensi/pembersihan request/rate-limit sesuai kebijakan setelah backend
  aktif; tidak ada cron atau penghapusan otomatis dalam draft ini.
- App Check belum diwajibkan pada callable agar tidak memblokir client sebelum
  provider dipasang. Role fresh, pembatasan percobaan dan admin approval tetap
  berlaku. Rencana abuse control production dan pengujian akun nyata diperlukan.

Aktivasi Firebase adalah tindakan terpisah setelah paket konkret direview. Paket
ini tidak menjalankan firebase deploy. Windows belum dikerjakan.
