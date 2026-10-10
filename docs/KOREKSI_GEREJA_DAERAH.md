# Koreksi gereja dan daerah

Superadmin dapat mengedit nama gereja melalui Kelola Gereja. Pada daftar daerah,
menu di samping nama daerah menyediakan Edit Nama dan Hapus Daerah.

Nama daerah yang diperbarui adalah label tampilan; identitas daerah tetap sama
agar pengurus, surat, keuangan, dan izin akun yang sudah ada tetap terhubung.
Gereja baru yang memilih label tersebut menggunakan identitas daerah yang sama.

Hapus Gereja dan Hapus Daerah dipakai untuk memperbaiki entri kosong yang salah
terbuat. Penghapusan ditolak jika pemeriksaan menemukan akun, jemaat, atau
riwayat terkait. Gereja yang sedang dibuka juga tidak dapat dihapus.
Entri dipindahkan ke arsip, tidak dihapus permanen dari Firebase, dan kode
undangannya dinonaktifkan. Menu Arsip di Kelola Gereja menyediakan Pulihkan.
Mengarsipkan semua gereja kosong suatu daerah menghilangkan daerah dari daftar
aktif; memulihkan gereja menampilkan daerah itu kembali.

Pemeriksaan menggunakan akun superadmin terbaru dari server, bukan hanya
status yang tersimpan di perangkat. Tidak ada data produksi yang diubah oleh
pengujian otomatis. Aturan Firestore tetap perlu membatasi perubahan dokumen
gereja kepada superadmin di server; pembatasan aplikasi tidak menggantikan Rules.
