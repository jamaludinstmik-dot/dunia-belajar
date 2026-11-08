# Dunia Belajar (versi Supabase)

Portal pembelajaran dengan login guru/siswa, database, dan penyimpanan file.

## Isi folder
- `index.html` : seluruh aplikasi (satu file)
- `supabase_setup.sql` : tabel, aturan akses (RLS), dan storage

## Langkah setup

1. **Buat proyek** gratis di https://supabase.com.
2. **Jalankan SQL**: buka *SQL Editor > New query*, tempel isi `supabase_setup.sql`, klik *Run*.
3. **Isi kunci**: buka *Project Settings > API*. Salin **Project URL** dan **anon public key**, lalu tempel di bagian `KONFIGURASI` pada awal `<script>` di `index.html`.
   Jangan pernah memakai `service_role key` di file ini.
4. **Buka `index.html`** di browser (atau unggah ke hosting statis seperti Netlify, Vercel, GitHub Pages, atau Cloudflare Pages) lalu daftar akun.
5. **Jadikan akun Anda guru**: di SQL Editor jalankan
   ```sql
   update public.profiles set role = 'guru'
   where id = (select id from auth.users where email = 'EMAIL-ANDA');
   ```
   Keluar lalu masuk lagi. Semua akun lain yang mendaftar otomatis menjadi siswa.
6. **(Opsional)** Di *Authentication > Providers > Email*, matikan *Confirm email* bila tidak ingin siswa mengonfirmasi lewat email.
   Di *Authentication > URL Configuration*, isi *Site URL* dengan alamat tempat Anda meng-host halaman ini.

## Apa yang berubah dari versi sebelumnya
- Data tersimpan permanen di database, file di storage privat (link bertanda tangan, berlaku 1 jam).
- Peran guru/siswa ditegakkan oleh **database (RLS)**, bukan hanya tombol yang disembunyikan.
- Pengumpulan tugas sungguhan: file tersimpan, divalidasi (PDF/PNG, maks 5 MB), ditolak setelah deadline (dicek juga di server), dan guru bisa memberi nilai.
- Absensi tersimpan, satu kali per hari, tanggal ditentukan server (WIB). Guru melihat rekap per tanggal dan siswa yang belum absen.
- Evaluasi: guru menambahkan link ujian eksternal (Google Form, CBT, dll).
- Semua input ditampilkan sebagai teks biasa (tanpa `innerHTML`), link dibatasi `http(s)`, sehingga celah XSS tertutup.
- Guru dapat menghapus konten; URL (`#materi/kelas-11`) bisa dibuka langsung dan tahan refresh.

## Catatan
- Tailwind lewat CDN cocok untuk sekolah kecil/prototipe. Untuk skala besar, build Tailwind sendiri.
- Paket gratis Supabase cukup untuk kelas kecil-menengah (batas storage 1 GB). Proyek gratis akan di-pause bila tidak aktif lama.
- Berkas siswa yang dikumpulkan tidak bisa dilihat siswa lain, hanya pemiliknya dan guru.
