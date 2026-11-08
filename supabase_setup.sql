-- =====================================================================
-- DUNIA BELAJAR - Skema Supabase
-- Jalankan seluruh file ini di: Supabase Dashboard > SQL Editor > New query
-- =====================================================================

-- ---------- 1. PROFIL & PERAN ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text not null default '',
  role       text not null default 'siswa' check (role in ('guru','siswa')),
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

create or replace function public.is_guru()
returns boolean
language sql security definer stable
set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'guru');
$$;

-- Setiap akun baru otomatis menjadi 'siswa'. Peran guru hanya bisa diberikan lewat SQL Editor.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''), 'siswa');
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_guru());

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Pengguna hanya boleh mengubah nama, bukan peran.
revoke update on public.profiles from anon, authenticated;
grant  update (full_name) on public.profiles to authenticated;

-- ---------- 2. TABEL KONTEN ----------
create table if not exists public.lkpd (
  id         uuid primary key default gen_random_uuid(),
  judul      text not null,
  file_path  text not null,
  file_name  text not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.latihan (
  id         uuid primary key default gen_random_uuid(),
  judul      text not null,
  file_path  text not null,
  file_name  text not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.games (
  id         uuid primary key default gen_random_uuid(),
  nama       text not null,
  link       text not null check (link ~* '^https?://'),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.materi (
  id         uuid primary key default gen_random_uuid(),
  judul      text not null,
  kelas      text not null check (kelas in ('kelas-10','kelas-11','kelas-12')),
  tipe       text not null check (tipe in ('teks','pdf','video')),
  isi        text,
  file_path  text,
  file_name  text,
  video_url  text check (video_url is null or video_url ~* '^https?://'),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.tugas (
  id         uuid primary key default gen_random_uuid(),
  judul      text not null,
  deskripsi  text not null,
  deadline   timestamptz not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.evaluasi (
  id         uuid primary key default gen_random_uuid(),
  judul      text not null,
  deskripsi  text,
  link       text not null check (link ~* '^https?://'),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Semua pengguna login boleh membaca; hanya guru yang boleh menambah/ubah/hapus.
do $$
declare t text;
begin
  foreach t in array array['lkpd','latihan','games','materi','tugas','evaluasi'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_write', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_select', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.is_guru()) with check (public.is_guru())', t || '_write', t);
  end loop;
end $$;

-- ---------- 3. PENGUMPULAN TUGAS ----------
create table if not exists public.pengumpulan (
  id             uuid primary key default gen_random_uuid(),
  tugas_id       uuid not null references public.tugas(id) on delete cascade,
  siswa_id       uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  file_path      text not null,
  file_name      text not null,
  nilai          numeric check (nilai is null or (nilai >= 0 and nilai <= 100)),
  dikumpulkan_at timestamptz not null default now(),
  unique (tugas_id, siswa_id)
);
alter table public.pengumpulan enable row level security;

drop policy if exists pengumpulan_select on public.pengumpulan;
create policy pengumpulan_select on public.pengumpulan
  for select to authenticated
  using (siswa_id = auth.uid() or public.is_guru());

-- Siswa hanya bisa mengumpulkan atas namanya sendiri dan sebelum deadline.
drop policy if exists pengumpulan_insert on public.pengumpulan;
create policy pengumpulan_insert on public.pengumpulan
  for insert to authenticated
  with check (
    siswa_id = auth.uid()
    and exists (select 1 from public.tugas t where t.id = tugas_id and t.deadline > now())
  );

drop policy if exists pengumpulan_update on public.pengumpulan;
create policy pengumpulan_update on public.pengumpulan
  for update to authenticated
  using (
    public.is_guru()
    or (siswa_id = auth.uid()
        and exists (select 1 from public.tugas t where t.id = tugas_id and t.deadline > now()))
  )
  with check (
    public.is_guru()
    or (siswa_id = auth.uid()
        and exists (select 1 from public.tugas t where t.id = tugas_id and t.deadline > now()))
  );

drop policy if exists pengumpulan_delete on public.pengumpulan;
create policy pengumpulan_delete on public.pengumpulan
  for delete to authenticated
  using (public.is_guru());

-- Siswa tidak boleh mengisi/mengubah nilai sendiri.
create or replace function public.protect_nilai()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.is_guru() then
    if tg_op = 'INSERT' then
      new.nilai := null;
    else
      new.nilai := old.nilai;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists pengumpulan_protect_nilai on public.pengumpulan;
create trigger pengumpulan_protect_nilai
  before insert or update on public.pengumpulan
  for each row execute function public.protect_nilai();

-- ---------- 4. ABSENSI ----------
create table if not exists public.absensi (
  id         uuid primary key default gen_random_uuid(),
  siswa_id   uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  tanggal    date not null default ((now() at time zone 'Asia/Jakarta')::date),
  status     text not null check (status in ('Hadir','Izin','Sakit')),
  created_at timestamptz not null default now(),
  unique (siswa_id, tanggal)
);
alter table public.absensi enable row level security;

-- Tanggal selalu ditentukan server (WIB), tidak bisa dipalsukan dari browser.
create or replace function public.set_absensi_tanggal()
returns trigger
language plpgsql
as $$
begin
  new.tanggal := (now() at time zone 'Asia/Jakarta')::date;
  return new;
end;
$$;

drop trigger if exists absensi_set_tanggal on public.absensi;
create trigger absensi_set_tanggal
  before insert on public.absensi
  for each row execute function public.set_absensi_tanggal();

drop policy if exists absensi_select on public.absensi;
create policy absensi_select on public.absensi
  for select to authenticated
  using (siswa_id = auth.uid() or public.is_guru());

drop policy if exists absensi_insert on public.absensi;
create policy absensi_insert on public.absensi
  for insert to authenticated
  with check (siswa_id = auth.uid());

drop policy if exists absensi_delete on public.absensi;
create policy absensi_delete on public.absensi
  for delete to authenticated
  using (public.is_guru());

-- ---------- 5. STORAGE (bucket privat 'files') ----------
-- Struktur path:
--   lkpd/..., latihan/..., materi/...        -> diunggah guru, dibaca semua
--   tugas/<id_siswa>/<id_tugas>/<file>       -> diunggah siswa, dibaca siswa tsb + guru
insert into storage.buckets (id, name, public, file_size_limit)
values ('files', 'files', false, 10485760)
on conflict (id) do update set public = false, file_size_limit = 10485760;

drop policy if exists files_select on storage.objects;
create policy files_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'files'
    and (
      (storage.foldername(name))[1] <> 'tugas'
      or public.is_guru()
      or (storage.foldername(name))[2] = auth.uid()::text
    )
  );

drop policy if exists files_insert on storage.objects;
create policy files_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'files'
    and (
      public.is_guru()
      or ((storage.foldername(name))[1] = 'tugas' and (storage.foldername(name))[2] = auth.uid()::text)
    )
  );

drop policy if exists files_delete on storage.objects;
create policy files_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'files'
    and (
      public.is_guru()
      or ((storage.foldername(name))[1] = 'tugas' and (storage.foldername(name))[2] = auth.uid()::text)
    )
  );

-- ---------- 6. JADIKAN AKUN TERTENTU SEBAGAI GURU ----------
-- Daftar dulu lewat halaman web, lalu jalankan (ganti emailnya):
--
--   update public.profiles
--   set role = 'guru'
--   where id = (select id from auth.users where email = 'guru@sekolah.sch.id');
