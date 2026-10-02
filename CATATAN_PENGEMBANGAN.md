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
- Tambah Akses Cepat: Jadwal, Doa, Chat, Galeri, Alkitab, Renungan, Lagu; Data Jemaat hanya untuk admin/superadmin.
- Ayat home tidak lagi berubah akibat ketukan tidak sengaja; diperlakukan sebagai Ayat Hari Ini selama sesi/hari.
- Empty state rekening tetap aman.

## Fase 4 — Pusat Daerah / role
- Superadmin tetap memiliki kewenangan penuh; Mode Pantau bukan pembatasan read-only.
- Admin Daerah memakai `adminDaerahArea`; Gembala/BPJ dapat fallback ke `userDaerah`.
- Tidak ada perubahan field Firebase atau migrasi daerah.

## Fase 5 — Hardening/pengembangan aman
- Mute chat sekarang berlaku untuk semua tipe pesan (teks, gambar, dokumen, audio), bukan teks saja.
- Perubahan yang membutuhkan backend/schema baru sengaja ditunda agar kompatibilitas aplikasi lama terjaga.

## Temuan penting yang masih harus ditangani setelah APK diuji
1. OneSignal REST key dan Telegram bot token masih berpotensi berada di client APK; idealnya pengiriman push/media server-side.
2. Firestore/Storage Security Rules tidak ada di repo sehingga keamanan server-side belum dapat diverifikasi dari source.
3. Claim/sinkronisasi jemaat dengan nomor telepon + tahun lahir perlu diperkuat server-side.
4. Role/privilege write dari client harus dijamin oleh Security Rules.
5. Kode undangan gereja perlu uniqueness yang lebih kuat tanpa memutus kode lama.
6. Pengumuman/badge unread/offline dashboard yang benar membutuhkan desain data/backend; jangan ditambahkan sebelum strategi kompatibilitas disepakati.
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
