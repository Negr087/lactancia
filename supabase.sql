-- Ejecutar en Supabase → SQL Editor. Se puede volver a correr sin romper nada.

-- 1) Tabla de tomas ---------------------------------------------------------
create table if not exists public.tomas (
  id         text primary key,
  tipo       text   not null check (tipo in ('materna','formula','teta')),
  t          bigint not null,          -- inicio, en ms (epoch)
  fin        bigint,                   -- fin de la teta, en ms (null = en curso)
  ml         integer check (ml is null or ml between 1 and 1000),
  updated_at timestamptz not null default now()
);
alter table public.tomas
  add column if not exists user_id uuid default auth.uid() references auth.users(id) on delete set null;
create index if not exists tomas_t_idx on public.tomas (t desc);

-- 2) Lista de personas autorizadas (por email) ------------------------------
create table if not exists public.familia (
  email text primary key
);
alter table public.familia enable row level security;
revoke all on public.familia from anon;
drop policy if exists "ver mi membresia" on public.familia;
create policy "ver mi membresia" on public.familia
  for select to authenticated
  using (lower(email) = lower(auth.jwt() ->> 'email'));

create or replace function public.es_familia()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.familia
    where lower(email) = lower(auth.jwt() ->> 'email')
  );
$$;
revoke execute on function public.es_familia() from public, anon;
grant execute on function public.es_familia() to authenticated;

-- 3) Permisos: solo usuarios logueados que estén en "familia" ---------------
alter table public.tomas enable row level security;
revoke all on public.tomas from anon;
drop policy if exists "tomas acceso publico" on public.tomas;   -- la política abierta anterior
drop policy if exists "familia lee"    on public.tomas;
drop policy if exists "familia crea"   on public.tomas;
drop policy if exists "familia edita"  on public.tomas;
drop policy if exists "familia borra"  on public.tomas;
create policy "familia lee"   on public.tomas for select to authenticated using (public.es_familia());
create policy "familia crea"  on public.tomas for insert to authenticated with check (public.es_familia());
create policy "familia edita" on public.tomas for update to authenticated using (public.es_familia()) with check (public.es_familia());
create policy "familia borra" on public.tomas for delete to authenticated using (public.es_familia());

-- 4) Tiempo real ------------------------------------------------------------
do $$ begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'tomas') then
    alter publication supabase_realtime add table public.tomas;
  end if;
end $$;

-- 5) Agregá los emails que pueden entrar (cambialos por los reales) ----------
insert into public.familia (email) values
  ('spibanez87@gmail.com'),
  ('otro-email@ejemplo.com')
on conflict do nothing;
