# Storage Rules: kandidat review, tidak di-deploy

Source Flutter `1272a970f585d63edda8ecbf34b5b1df98ebf85b`; rules masukan pengguna
disalin dengan izin yang sama ke `storage.supplied.rules`. Kandidat
`storage.compat.rules` dipasangkan dengan `firestore.compat.rules`; **tidak boleh
dipasang sendirian bersama Firestore rules lama**, karena rules lama membolehkan
pengguna mengubah role sendiri. Tidak ada file/data/rules produksi diubah.

## Temuan

- `match /{allPaths=**}` mengizinkan seluruh akun login overwrite/hapus file
  orang lain dan melewati aturan khusus foto jemaat/aset. Akun diblokir pun lolos.
- Admin lama tidak dibatasi gereja. Tidak ada validasi ukuran/MIME atau kepemilikan.
- Rules khusus aset menggunakan `aset_gereja_photos`, tetapi uploader Flutter
  sekarang menulis `aset_gereja/{churchId}_{timestamp}.jpg`.
- Foto profil, header, pengurus dan info daerah hanya bekerja karena wildcard.

## Kontrak path dan perubahan

| Path aktual | Penulis | Pembaca SDK |
| --- | --- | --- |
| users/{uid}/profil_{uid}[_suffix].jpg | Pemilik akun aktif; folder juga menerima nama foto lama | Akun aktif |
| churches/{churchId}/foto_jemaat/{file} | Admin gereja tersebut atau superadmin | Akun aktif |
| gereja/{churchId}/header_{timestamp}.jpg, gembala_{timestamp}.jpg | Admin gereja tersebut atau superadmin | Akun aktif |
| gereja/{churchId}/pengurus/{id}.jpg | Admin gereja tersebut atau superadmin | Akun aktif |
| aset_gereja/{churchId}_{timestamp}.jpg | Admin gereja prefix tepat atau superadmin | Akun aktif |
| aset_gereja_photos/{file} (legacy, bukan uploader sekarang) | Superadmin; scope gereja filename lama belum terbukti | Akun aktif |
| info_daerah/{area}/doc_{timestamp}.{ext} | adminDaerahArea tepat atau superadmin, bukan Gembala/BPJ | Akun aktif |

Gallery/chat pada source ini memakai Telegram/Cloudinary, bukan Firebase Storage;
tidak dibuat wildcard upload chat/gallery Firebase tanpa kontrak path yang nyata.
Reads get tetap luas untuk kompatibilitas foto profil/buku/pengurus dan lampiran
yang dibagikan ke chat lokal. Listing dan path tak dikenal ditolak; source tidak
menggunakan Storage list. Ini belum memberi isolasi baca lintas gereja/daerah.

Upload foto dibatasi >0 sampai 10 MiB, MIME JPEG/PNG/WebP. Lampiran sampai 20 MiB,
MIME foto/PDF/Word/Excel/PowerPoint dan extension yang sama dengan picker/scanner.
Ini batas kandidat, **bukan klaim aplikasi lama sudah memeriksa ukuran**. APK lama
dapat menampilkan error upload pada file besar, HEIC/GIF, extension huruf besar,
atau MIME `application/octet-stream`. Sebelum rollout, tambahkan pesan validasi
client dan metadata MIME eksplisit, lalu uji perangkat/picker/file representatif.
MIME dideklarasikan client: rules tidak membuktikan isi bytes merupakan gambar
valid atau dokumen bebas malware. Delete dipisah dari create/update agar tidak
memeriksa request.resource kosong. Metadata update juga harus memenuhi batas.

Flat asset scope menggunakan perbandingan substring literal, bukan interpolasi
churchId ke regex. Timestamp suffix wajib angka sehingga admin gereja `a` tidak
bisa mengubah file gereja `a_b`. File lama dengan pola berbeda tidak dimigrasi;
perlu inventaris/mapping sebelum izin edit/hapus admin lokal diperluas.

## Pengujian

`npm run test:storage` menjalankan Firestore dan Storage pada localhost dengan
proyek `demo-gereja-rules` yang sama. Tes tidak memakai credentials/secrets atau
project produksi. Pertama reproduksi bypass rules lama, kemudian candidate diuji
melawan upload/hapus lintas akun/gereja, blocked, role revoke, path aktual,
legacy reads, scope prefix, MIME, ukuran, metadata update, delete dan path unknown.
Fixtures metadata sintetis; bukan tes decoder gambar, UI Flutter atau jaringan.
Firestore regression suite tetap dijalankan terpisah.

Rules melakukan akses cross-service hanya ke satu path users/UID (pemanggilan
berulang path identik dapat di-cache), tidak mencari semua gereja/asset. Jangan
menganggap emulator membuktikan semua limit layanan produksi atau konfigurasi IAM.
Integrasi Firestore–Storage membutuhkan izin layanan terkait saat deploy; tidak
ada perubahan IAM dilakukan pada audit ini.

## Batasan sebelum produksi

1. Firebase download URLs bertoken yang sudah dibagikan adalah bearer URLs.
   Mengetatkan SDK rules tidak otomatis menarik kembali URL tersebut. Tidak ada
   token lama dicabut atau file dihapus pada audit ini. Jangan klaim aturan get
   menjadikan semua foto privat.
2. Kandidat hanya diuji terhadap source commit di atas, bukan semua APK historis.
   Legacy aset, worker, path tambahan, file besar dan MIME aktual perlu staging.
3. Doa privat, bukti undangan/tautan, moderasi kamus dan integritas pasangan ledger
   tetap blockers Firestore yang dijelaskan di README.md. Storage rules bukan
   pengganti backend verifikasi identitas. Pengembangan Windows tetap ditahan.
4. Langkah berikutnya ialah patch client untuk query doa yang aman dan validasi
   upload, serta rancangan approval/backend join/link yang tidak mempercayai
   pemeriksaan client. Tidak ada perubahan skema/migrasi produksi dilakukan.

Referensi: https://firebase.google.com/docs/storage/security/rules-conditions,
https://firebase.google.com/docs/emulator-suite/connect_storage,
https://firebase.google.com/docs/reference/security/storage.
