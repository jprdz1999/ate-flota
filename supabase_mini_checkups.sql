-- Mini-Checkups de Flota — esquema para correr a mano en el SQL editor de Supabase.
-- Este repo no tiene migrations tooling (ver index.html): todas las tablas viven
-- directamente en el proyecto de Supabase, sin versión en el código.

create table bases (
  id text primary key,
  nombre text not null
);
insert into bases (id, nombre) values
  ('central_vieja_gdl', 'Central Vieja GDL'),
  ('etzatlan', 'Etzatlán');

create table operadores (
  id text primary key,
  nombre_canonico text not null,
  created_at timestamptz not null default now()
);

create table operador_alias (
  id text primary key,
  operador_id text not null references operadores(id),
  alias text not null,
  created_at timestamptz not null default now()
);

create table chequeos_rapidos (
  id text primary key,
  bus_id text not null references buses(id),
  base_id text not null references bases(id),
  operador_id text references operadores(id),
  operador_texto text not null,
  usuario_email text,
  fecha date not null,
  ts bigint not null,
  fotos jsonb not null default '{}'::jsonb,
  marcas_nuevas jsonb not null default '[]'::jsonb,
  marcas_acumuladas jsonb not null default '[]'::jsonb,
  chequeo_anterior_id text references chequeos_rapidos(id),
  dano_nuevo_detectado boolean not null default false,
  severidad_maxima text,
  alerta_atendida boolean not null default false,
  notas text,
  created_at timestamptz not null default now()
);

-- Storage: bucket privado + URLs firmadas generadas en cliente (no público).
insert into storage.buckets (id, name, public) values ('chequeos', 'chequeos', false);
create policy "chq authenticated read" on storage.objects for select to authenticated using (bucket_id = 'chequeos');
create policy "chq authenticated write" on storage.objects for insert to authenticated with check (bucket_id = 'chequeos');
create policy "chq authenticated update" on storage.objects for update to authenticated using (bucket_id = 'chequeos');

-- RLS: mismo modelo permisivo (autenticado = acceso completo) que ya usa el resto
-- de la app — loadFromSupabase() hace select('*') sin filtro y la segregación por
-- ciudad ocurre solo en cliente vía cityBuses(). Si el proyecto real tiene RLS más
-- estricto en buses/service_logs de lo que el archivo sugiere, ajustar antes de correr.
alter table bases enable row level security;
alter table operadores enable row level security;
alter table operador_alias enable row level security;
alter table chequeos_rapidos enable row level security;
create policy "authenticated full access" on bases for all to authenticated using (true) with check (true);
create policy "authenticated full access" on operadores for all to authenticated using (true) with check (true);
create policy "authenticated full access" on operador_alias for all to authenticated using (true) with check (true);
create policy "authenticated full access" on chequeos_rapidos for all to authenticated using (true) with check (true);
