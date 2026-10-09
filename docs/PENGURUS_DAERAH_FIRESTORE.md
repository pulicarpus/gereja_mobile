# Akses Pengurus Daerah

Halaman pengurus memakai `struktur_pengurus_daerah/{idDaerah}` dan subkoleksi
`penasehat`, `mkdp`, `bpk`, serta `komisi`. Aturan Firebase yang hanya mengenali
`pengurus_daerah` (format daftar lama) belum tentu mengizinkan jalur baru ini.
Galat `permission-denied` tidak dapat diperbaiki hanya dengan memasang APK baru.

`firebase/firestore.rules` berisi aturan lengkap yang dikirim pengguna pada
9 Oktober 2026, dengan tambahan blok Pengurus Daerah di bawah. Izin lama
dipertahankan. File ini belum diterapkan ke Firebase produksi. Untuk Belitang,
salin seluruh isi file ke tab Rules lalu Publish setelah pemeriksaan emulator.

## Tambahan aturan untuk Belitang

Ini **draf tambahan**, bukan pengganti seluruh Rules produksi. Gabungkan blok
berikut **di dalam** `match /databases/{database}/documents` pada Firebase
Console → Firestore Database → Rules. Pertahankan semua aturan fitur lain.
Periksa aturan produksi terlebih dahulu: aturan `allow` yang lebih luas tetap
berlaku karena Firestore menggabungkan izin dengan OR.

Contoh ini menggunakan nama daerah persis `Belitang` dan ID `Belitang`.
Pastikan nilai `users/{uid}.adminDaerahArea` sesuai sebelum menerapkannya.
ID dalam aplikasi adalah `Uri.encodeComponent(namaDaerah.trim())`; nama dengan
spasi atau karakter khusus menghasilkan ID yang berbeda. Tambahkan pasangan
ID/nama yang sesuai untuk daerah lain, jangan membuka akses umum.

```text
function pdAccountActive() {
  return request.auth != null
    && exists(/databases/$(database)/documents/users/$(request.auth.uid))
    && get(/databases/$(database)/documents/users/$(request.auth.uid))
         .data.get('isBlocked', false) != true;
}

function pdArea(idDaerah) {
  // Tambahkan pemetaan ID/nama daerah yang benar di sini bila diperlukan.
  return idDaerah == 'Belitang' ? 'Belitang' : '';
}

function pdAuthorized(idDaerah) {
  return pdAccountActive() && pdArea(idDaerah) != ''
    && (
      get(/databases/$(database)/documents/users/$(request.auth.uid))
        .data.get('role', '') == 'superadmin'
      || get(/databases/$(database)/documents/users/$(request.auth.uid))
        .data.get('adminDaerahArea', '') == pdArea(idDaerah)
    );
}

match /struktur_pengurus_daerah/{idDaerah} {
  // Mengizinkan pembacaan dokumen yang belum dibuat agar posisi kosong tampil.
  allow get: if pdAuthorized(idDaerah);
  allow create, update: if pdAuthorized(idDaerah)
    && request.resource.data.daerah == pdArea(idDaerah);
  // Aplikasi tidak menghapus dokumen utama; subkoleksi harus tetap bertaut.

  match /{bagian}/{anggotaId} {
    allow read: if bagian in ['penasehat', 'mkdp', 'bpk', 'komisi']
      && pdAuthorized(idDaerah);
    allow create, update: if bagian in ['penasehat', 'mkdp', 'bpk', 'komisi']
      && pdAuthorized(idDaerah)
      && request.resource.data.daerah == pdArea(idDaerah)
      && getAfter(/databases/$(database)/documents/struktur_pengurus_daerah/$(idDaerah))
        .data.daerah == pdArea(idDaerah);
    allow delete: if bagian in ['penasehat', 'mkdp', 'bpk', 'komisi']
      && pdAuthorized(idDaerah)
      && resource.data.daerah == pdArea(idDaerah);
  }
}
```

## Pemeriksaan sebelum Publish

Dengan Rules Playground/emulator, pastikan akun admin Belitang dapat membaca
dokumen utama yang belum ada dan menanyakan keempat subkoleksi; penambahan
pengurus inti berhasil; komisi beserta anggota dapat dibuat dan diubah.
Akun tanpa login, akun diblokir, dan admin daerah lain harus ditolak.
Penulisan `daerah` yang tidak sesuai dengan ID juga harus ditolak.

Rules Storage untuk foto adalah aturan terpisah. Blok di atas memperbaiki akses
data Firestore, bukan izin upload foto. Jangan mengganti seluruh aturan Storage
tanpa memeriksa aturan yang sudah berlaku.

Setelah Rules digabungkan dan dipublikasikan, tekan **Coba lagi** pada halaman
Pengurus Daerah. Perubahan Rules belum dipublikasikan oleh perubahan kode ini.

## Pengujian lokal

Dengan Node.js 22+ dan Java 21+, jalankan `npm install` lalu `npm test` dari
folder `firebase`. Tes memakai proyek emulator `demo-gkii-pengurus` dan tidak
mengakses Firebase produksi. Tes ini sudah lulus: pembacaan saat dokumen utama
belum ada, query subkoleksi kosong, pembuatan induk/komisi atomik, edit anggota,
penolakan akun daerah lain/tanpa login/diblokir, dan izin modul lama yang diuji.
