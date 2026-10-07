# Audit Firestore — kandidat transisi, belum untuk deploy

Sumber aplikasi: `perbaikan-fitur-daerah` pada commit
`1272a970f585d63edda8ecbf34b5b1df98ebf85b`. Rules masukan pengguna disalin
ke `firestore.supplied.rules` dengan komentar/format disederhanakan, izin sama.
`firestore.compat.rules` adalah kandidat review, **bukan rules produksi final**.
Tidak ada data produksi dibaca, ditulis, dimigrasi, atau dihapus oleh pekerjaan ini.
Tidak ada kode Flutter, konfigurasi Android, Storage rules, atau cabang Windows diubah.

## Temuan dan perubahan

| Temuan pada rules masukan | Penanganan kandidat |
| --- | --- |
| Pemilik users bisa mengangkat diri menjadi admin/superadmin, membuka blokir, menunjuk diri sebagai pengurus/admin daerah | Self update hanya nama/foto, penetapan gereja pertama, dan transaksi tautan yang konsisten. Create akun tidak boleh memuat privilege tambahan. |
| Wildcard rekursif churches mengizinkan semua tulisan, termasuk jemaat/aset/chat | Tidak ada wildcard write rekursif; setiap modul disebutkan. Match dinamis satu tingkat dibatasi daftar nama modul. |
| Admin lokal bisa mengubah gereja/pengguna gereja lain | Admin dibatasi churchId asal, target normal user; jabatan daerah dan pemindahan gereja hanya superadmin. Self role change dan perubahan target superadmin ditolak. |
| Profil baru terblokir jika jemaat dibuat admin-only | Self link mendapat pengecualian update `uid` saja, dikaitkan dengan users melalui `getAfter`. Dua sisi harus konsisten, kategori mengikuti buku, buku milik orang lain tidak boleh diambil. |
| Semua login bisa mengubah keuangan dan info daerah | Kas/jadwal kategori mengikuti pengurus kategori; perpuluhan/admin umum mengikuti admin lokal. Keuangan daerah mempertahankan penulis superadmin, adminDaerahArea, Gembala/BPJ satu daerah. Publikasi info hanya superadmin/admin daerah. |
| Identitas chat dan mute hanya diperiksa client | Sender UID, kepemilikan edit/hapus, kategori, mute ditegakkan server. Format lama senderId dan baru pengirimId tetap didukung. |
| Siapa pun mengubah lagu/kamus orang lain | Lagu admin/superadmin; kamus hanya kontribusi pertama, koreksi/hapus superadmin. Tidak mengubah format cache AI lama. |
| Akun diblokir tetap bisa mengakses data | Akun diblokir hanya boleh get dokumen dirinya untuk tampilan login. Modul ditolak. |
| Users/notes berisiko terbuka lintas akun | Users dibaca sendiri atau admin berwenang; notes selalu hanya pemilik, termasuk terhadap admin/superadmin. |
| Koleksi tak terpakai/unknown terbuka | pending_notifications, chats_daerah dan path tak dikenal ditolak karena tidak ditemukan pemanggil pada source yang diaudit. Backend Admin SDK tidak memakai client rules. Kontrak worker harus diperiksa sebelum rollout. |

## Pemetaan kontrak aplikasi

| Source Flutter | Path/field yang dipertahankan |
| --- | --- |
| login_page, validasi_gereja_page | users default role=user, isBlocked=false, isPengurus=false; query churches.kodeUndangan; hanya penetapan churchId/churchName awal |
| profile_service, sinkronisasi_jemaat_page | users.jemaatId/kelompok dan churches/{id}/jemaat/{id}.uid atomik; kategori legacy huruf kecil/spasi didukung |
| management_service | query users.where(churchId), role user/admin, isPengurus, kelompok, adminDaerahArea; gereja pindah hanya akun belum tertaut |
| main | fotoGerejaUrl, rekening, nama/foto dan kontak gembala dapat diubah admin lokal; metadata gereja lain superadmin |
| pengurus_repository/detail_seksi | bpj_bpk, bpj_penasehat, bpj_seksi admin lokal/superadmin |
| jadwal/susunan_acara | jadwal.kategoriKegiatan; pengumuman/utama dan pengumuman/pengumuman_{kategori} |
| gallery/detail_folder | gallery_folders dan gallery_folders_{kategori}; subkoleksi images; bukan collection gallery generik |
| chatroom/info_surat | chats/chats_{kategori}, muted_chats/muted_chats_{kategori}; pengirimId atau senderId |
| aset_gereja | aset_gereja.gerejaId (bukan churchId); path lokal aset lama turut dilindungi |
| keuangan/perpuluhan | churches/{id}/transaksi.kategori dan perpuluhan; format nominal lama tidak dimigrasi |
| keuangan_daerah/info_surat | global collections, field daerah; adminDaerahArea terpisah dari role, bukan role admin_daerah |
| kamus/notes/doa | kamus_global/{kata}, users/{uid}/notes, prayers.churchId/uid/isPrivat/daftarAmin |

## Batasan yang MENGHALANGI deploy produksi final

1. **Doa privat belum aman di kandidat transisi.** `doa_page.dart` mengambil semua
   doa gereja lalu menyaring `isPrivat` di perangkat. Kandidat mempertahankan query
   agar aplikasi lama tetap berjalan, sehingga sesama anggota gereja masih bisa
   membaca doa privat lewat SDK. Batasan ini diuji eksplisit, bukan dianggap lulus
   keamanan. Rules final harus mengizinkan pemilik serta admin/gembala, dan query
   aplikasi biasa harus dipisah publik/pemilik. Dokumen lama tanpa flag `isPrivat`
   memerlukan strategi kompatibilitas tersendiri; tidak dilakukan backfill.
2. **Bukti undangan dan bukti identitas tautan belum tersedia di server.** Query
   kode undangan, nomor telepon dan pemeriksaan tahun lahir saat ini dilakukan
   client. Rules tidak bisa memastikan pemeriksaan itu dijalankan. Kandidat
   membatasi penetapan gereja sekali dan tautan dua sisi, tetapi pemakai SDK masih
   dapat memilih gereja pertama yang ada serta mengklaim buku belum tertaut.
   Direktori churches juga memuat kodeUndangan yang dibaca client. Solusi final:
   verifikasi/join/link melalui backend terpercaya atau bukti yang diverifikasi
   server; phone OTP/approval admin lebih kuat dari tahun lahir yang dapat dibaca.
   Jangan menyebut sinkronisasi telah membuktikan identitas manusia.
3. **Kamus kontribusi pertama belum memiliki moderasi isi.** Validasi panjang dan
   larangan overwrite mengurangi kerusakan, bukan membuktikan jawaban berasal dari
   Gemini. Backend/approval diperlukan untuk melawan poisoning kontribusi pertama.
4. **Perpuluhan daerah dan kas masih dapat ditulis terpisah oleh penulis sah.**
   Batch aplikasi sekarang didukung, tetapi rules ini belum memaksakan kesetaraan
   nilai kedua dokumen. Kontrak ledger lengkap harus dirancang dan diuji sebelum
   menyatakan integritas keuangan server selesai.
5. **Storage Rules belum diberikan.** Akses upload/foto, batas tipe/ukuran, dan
   penghapusan file belum diaudit lewat rules. REST key OneSignal/Telegram di APK
   tidak diamankan oleh Firestore rules; perlu backend terpisah, bukan ubah data.
6. **Bukan verifikasi seluruh versi APK lama atau worker.** Source yang diuji
   adalah commit di atas. Koleksi settings/gallery tambahan, client worker
   pending_notifications/chats_daerah, atau APK historis yang menulis privilege
   bersama profil bisa ditolak. Inventaris versi aktif dan uji staging wajib
   sebelum aktivasi. Rules tidak memperbaiki role berbahaya yang sudah terlanjur
   tersimpan; diperlukan review administratif terpisah, tidak dilakukan di sini.

## Pengujian tanpa Firebase produksi

Jalankan dengan Node 22, Java 21:

```sh
cd security/firestore
npm install --ignore-scripts --no-audit --no-fund
npm test
```

Dependencies utama dipin exact; transitive install belum memakai lockfile.
Workflow `.github/workflows/firestore-rules.yml` melakukan langkah yang sama,
tanpa secrets, tanpa `firebase deploy`, hanya proyek `demo-*` dan emulator lokal.
Tes menolak berjalan bila FIRESTORE_EMULATOR_HOST bukan localhost/127.0.0.1.
Fixture sintetis meliputi role, blocked, gereja lain, regional, kategori legacy,
query scoped, tautan batch dan Amin format nama. Tidak ada akun produksi.

Hasil emulator hanya membuktikan operasi fixture. Tidak membuktikan seluruh data
legacy, indeks produksi, Storage, HTTP notification, UI di perangkat, atau semua
limit batch besar. Rules mempertahankan field tambahan pada dokumen legacy saat
update dengan memeriksa changed fields, bukan mengganti dokumen tersebut.

## Urutan tindak lanjut

1. Review kandidat dan hasil CI. Tetapkan kebijakan baca doa/daerah/jemaat dan
   kontrak worker yang belum ada. Jangan copy-paste kandidat sebagai rules final.
2. Siapkan query/flow verifikasi yang diperlukan di cabang uji; uji aplikasi lama
   dan baru pada staging/emulator dengan fixture representatif tanpa data produksi.
3. Selesaikan blockers di atas dan audit Storage Rules setelah tersedia.
4. Baru rencanakan aktivasi rules terkoordinasi. Tidak ada deployment pada audit ini.
5. Setelah kesesuaian Firebase disepakati, lanjut Windows di `fitur-windows`.

Referensi resmi: https://firebase.google.com/docs/firestore/security/rules-structure
(overlapping allow bersifat OR), https://firebase.google.com/docs/firestore/security/rules-query
(rules bukan filter), https://firebase.google.com/docs/firestore/security/rules-fields
(diff/affectedKeys), https://firebase.google.com/docs/rules/unit-tests
(rules-unit-testing), https://firebase.google.com/docs/emulator-suite/connect_firestore
(proyek demo tidak menggunakan sumber daya produksi).
