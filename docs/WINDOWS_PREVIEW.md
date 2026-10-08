# GKII Mobile — Windows x64 (versi uji)

Dasar: fix/profil-sederhana 42248b06f87c8129c7e3e0cb85e7fdd21979cc36.
Tidak mengaktifkan backend persetujuan/OTP. Firebase produksi, data, rules,
indeks, OAuth credentials, dan cabang Android tidak diubah oleh pekerjaan ini.

## Menjalankan

1. Ekstrak seluruh ZIP ke folder biasa, bukan jalankan dari dalam ZIP.
2. Jalankan gereja_mobile.exe. Semua DLL dan folder data harus tetap di sebelah EXE.
3. Buka Alkitab lokal untuk mencoba database dan tampilan tanpa login.
4. Login memakai akun Google yang sama seperti Android setelah konfigurasi
   Desktop tersedia. Penggunaan simpan/upload oleh pengguna memakai Firebase asli,
   seperti aplikasi Android, bukan database dummy.

Jika Windows melaporkan runtime Visual C++ hilang, pasang Microsoft Visual C++
Redistributable x64 dari https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist.
Paket ini portable, bukan installer, dan belum ditandatangani untuk distribusi publik.

## Login Google desktop

Plugin Google Sign-In Android tidak menyediakan login Windows. Build menggunakan
OAuth melalui browser sistem, loopback 127.0.0.1 port acak, state, nonce, dan PKCE
S256. Listener dibersihkan pada sukses/gagal/batal/timeout. Token tidak disimpan
atau dicetak oleh implementasi OAuth; Firebase menangani sesi autentikasi.
Signature ID token diverifikasi oleh Firebase, pemeriksaan claims lokal bukan
pengganti verifikasi signature.

Konfigurasi Desktop belum disediakan dalam repository atau paket. Untuk login:
- Di Google Cloud Console, pilih proyek gerejaappv2 yang sudah ada.
- Buat OAuth client jenis Desktop app (bukan Web application/Android).
- Unduh JSON OAuth, beri nama oauth-desktop.json, letakkan di sebelah EXE.
- Jangan mengganti OAuth client Android, konfigurasi Firebase, atau rules.

Pembuatan credential merupakan langkah pemilik proyek; tidak dilakukan otomatis.
Login nyata dan pembatasan API key/OAuth perlu diuji di perangkat. Akun maupun
kredensial produksi tidak digunakan dalam CI. Jika pemilik proyek belum membuat
credential, Alkitab lokal tetap tersedia dan login memberi pesan yang jelas.

## Dukungan fitur

- Database Alkitab menggunakan SQLite FFI dengan runtime sqlite3.dll di bundle.
- Playback video splash memakai video_player_win, audio/record memakai plugin yang
  mendukung Windows. Microphone/privacy settings dan codec OS perlu uji perangkat.
- Pemilihan gambar memakai file chooser; tombol kamera langsung chat disembunyikan.
- Scanner dokumen Android diganti pilihan file di desktop.
- Foto galeri disimpan ke lokasi yang dipilih, bukan API galeri HP.
- Kamus SABDA dibuka di browser sistem, karena WebView Flutter asli tidak mendukung
  Windows. Tidak perlu WebView2 untuk jalur ini.
- OneSignal push masuk tidak tersedia pada Windows; wrapper menghindari panggilan
  plugin Android/iOS di desktop. Fitur data/chat dapat dibuka setelah login.
- Tampilan memakai jendela resizable dari runner Flutter standar; layout desktop
  menyeluruh dan installer merupakan tahap berikut setelah uji fungsi utama.

## Batasan penting

Firebase SDK Flutter untuk Windows dinyatakan beta dan tidak ditujukan untuk
produksi oleh dokumentasi resmi: https://firebase.google.com/docs/flutter/setup.
Bundle ini untuk uji desktop, belum dinyatakan siap rollout gereja. Konfigurasi
Firebase desktop development memakai identifier Android existing, tidak membuat
registrasi Firebase baru. CI tidak membuktikan login nyata, akses data gereja,
seluruh menu di perangkat, kamera, codec, atau semua kondisi Windows.

Kunci layanan notifikasi/AI lama masih mengikuti konfigurasi aplikasi existing.
Tidak ada migrasi credential/backend dalam pekerjaan desktop ini.

## Build dari source

Windows dengan Flutter dan Visual Studio C++ Desktop workload:
Python 3 juga diperlukan untuk menyiapkan salinan pustaka native Firebase.

```powershell
./tool/prepare_windows.ps1
flutter pub get
# Siapkan lib/secrets.dart secara lokal; jangan commit credential.
flutter test
flutter build windows --release
```

Runner Windows dari build CI yang berhasil sudah disimpan dalam repository.
Script hanya membuat runner dari template SDK jika folder windows belum ada;
source Android/pubspec tidak digenerate ulang. Workflow mengekspor runner untuk review. Seluruh bundle Release harus dibagikan,
bukan hanya EXE. Workflow tidak deploy Firebase atau mengirim Telegram.

## Kompatibilitas CPU Windows

Firebase C++ SDK 12.7.0 membundel objek Snappy dengan instruksi BMI2 (`bzhi`).
Instruksi ini menyebabkan `c000001d` pada CPU tanpa BMI2 seperti Celeron N4500
ketika data terkompresi dibaca. Opsi compiler runner tidak mengubah pustaka
yang sudah dikompilasi. Build mengganti hanya objek Snappy dalam salinan arsip
Firebase di direktori build, kemudian menautkan Snappy 1.1.10 dari sumber dengan
BMI2, AVX/AVX2, SSSE3, dan CRC32 hardware dinonaktifkan. API dan format data
Snappy 1.1 tetap kompatibel; cache paket dan SDK asli tidak dimodifikasi.
Unduhan sumber dipin dengan SHA256 dan paket menyertakan lisensi Snappy.

CI menjalankan fixture dekompresi dan 21 kasus kompresi/dekompresi native.
Simbol PDB tersedia sebagai artifact terpisah `GKII-Mobile-Windows-debug-symbols`,
tanpa memperbesar ZIP portable. Uji startup CI memakai CPU runner GitHub;
uji login, pemuatan data, dan pembukaan ulang pada N4500 tetap diperlukan.
Simpan `oauth-desktop.json` lokal dan salin ke folder paket baru untuk pengujian.
