
-- MEMBUAT TABEL MATA PELAJARAN
create table if not exists public.mata_pelajaran (
  id uuid primary key default gen_random_uuid(),
  nama text not null,
  kelas text not null check (
    kelas in ('kelas-10', 'kelas-11', 'kelas-12')
  ),
  created_at timestamptz not null default now()
);

create unique index if not exists mata_pelajaran_kelas_nama_unique
on public.mata_pelajaran (kelas, lower(nama));

-- MENGHUBUNGKAN MATERI DENGAN MATA PELAJARAN
alter table public.materi
add column if not exists mata_pelajaran_id uuid;

-- MEMBUAT MATA PELAJARAN UMUM UNTUK MATERI LAMA
insert into public.mata_pelajaran (nama, kelas)
select 'Umum', kelas
from public.materi
group by kelas
on conflict do nothing;

update public.materi m
set mata_pelajaran_id = mp.id
from public.mata_pelajaran mp
where m.mata_pelajaran_id is null
and m.kelas = mp.kelas
and lower(mp.nama) = 'umum';

-- RELASI ANTAR TABEL
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'materi_mata_pelajaran_id_fkey'
    and conrelid = 'public.materi'::regclass
  ) then
    alter table public.materi
    add constraint materi_mata_pelajaran_id_fkey
    foreign key (mata_pelajaran_id)
    references public.mata_pelajaran(id)
    on delete restrict;
  end if;
end $$;

-- AKSES DATABASE
alter table public.mata_pelajaran enable row level security;

create policy "mata_pelajaran_select"
on public.mata_pelajaran
for select to authenticated
using (true);

create policy "mata_pelajaran_insert"
on public.mata_pelajaran
for insert to authenticated
with check (public.is_guru());

create policy "mata_pelajaran_update"
on public.mata_pelajaran
for update to authenticated
using (public.is_guru())
with check (public.is_guru());

create policy "mata_pelajaran_delete"
on public.mata_pelajaran
for delete to authenticated
using (public.is_guru());

-- MEMUAT ULANG SCHEMA SUPABASE
notify pgrst, 'reload schema';
