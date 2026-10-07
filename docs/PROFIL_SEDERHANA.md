# Profil sederhana tanpa backend baru

Cabang ini berasal dari versi Android perbaikan-fitur-daerah (1272a970f585d63edda8ecbf34b5b1df98ebf85b), mempertahankan perbaikan menu, profil/loading/refresh, dan seluruh tes regresi sebelumnya.

- Bergabung menggunakan kode undangan yang ada. Kode ambigu ditolak dan diverifikasi ulang dalam transaksi. Role dan tautan akun yang sudah tersimpan tidak direset pada cache.
- Tautan jemaat tetap melalui nomor telepon dan tahun lahir. Hasil lebih dari satu orang diarahkan ke admin. Transaksi membaca ulang akun/buku, menolak pemilik akun lain, perubahan gereja/nomor, dan kategori pengurus yang tidak sesuai. Ini pemeriksaan client, bukan bukti identitas atau pengamanan terhadap SDK yang dimodifikasi.
- Validasi ukuran dan signature file serta metadata MIME diterapkan pada upload. Foto maksimal 10 MiB, lampiran maksimal 20 MiB. Signature sederhana bukan pemindai malware.
- Tidak memakai Cloud Functions, OTP, atau persetujuan server. Draft tersebut tetap tersimpan di security/firestore-compatibility, tidak termasuk APK cabang ini.
- Tidak mengubah Firebase produksi, rules, indeks, skema data, token, atau konfigurasi Android. APK menggunakan Firebase aplikasi yang sudah ada; penggunaan fitur simpan/upload di perangkat tetap dapat menulis data sesuai tindakan pengguna.
- Query doa lama dipertahankan agar tidak memerlukan indeks/rules baru dan tidak menyembunyikan dokumen legacy. Privasi server doa belum diperketat; filter tampilan client tidak menggantikan rules.
- Tidak membuat proyek Firebase percobaan dan tidak mengubah cabang Windows. Build CI hanya menghasilkan APK, tidak deploy Firebase atau mengirim Telegram pada push.

APK lama dari cabang audit masih membutuhkan backend baru. Gunakan APK cabang fix/profil-sederhana untuk menguji alur sederhana; jangan menganggap APK audit telah berubah.
