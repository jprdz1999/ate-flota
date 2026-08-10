-- Rediseño Fases 2 y 4 — migraciones aplicadas a mano en Supabase (este repo no
-- tiene migrations tooling; se documentan aquí para historial). Ya corrieron vía
-- el MCP de Supabase el 2026-08-10.

-- ── Fase 2: odómetro obligatorio en el chequeo rápido ────────────────────────
alter table chequeos_rapidos add column if not exists km integer;

-- ── Fase 4: expediente de golpes acumulado por unidad ────────────────────────
create table danos (
  id              text primary key,
  bus_id          text not null references buses(id),
  x               numeric not null,          -- posición en el diagrama (0–100)
  y               numeric not null,
  descripcion     text not null,
  severidad       text not null default 'cosmetico',  -- cosmetico | seguridad
  fotos           jsonb not null default '[]'::jsonb,
  estado          text not null default 'activo',      -- activo | reparado
  -- Trazabilidad: inspección que lo detectó + ventana de tiempo + operador a cargo
  origen          text not null default 'chequeo',     -- chequeo | checklist
  inspeccion_id   text,                       -- chequeos_rapidos.id o service_logs.id
  operador_texto  text,
  base_id         text references bases(id),  -- base donde se detectó (fin de ventana)
  detectado_ts    bigint,                     -- ts de la inspección que lo detectó
  prev_base_id    text references bases(id),  -- base de la inspección anterior (inicio de ventana)
  prev_ts         bigint,                     -- ts de la inspección anterior
  fecha_deteccion date not null,
  reparado_fecha  date,
  reparado_nota   text,
  created_at      timestamptz not null default now()
);
create index danos_bus_estado_idx on danos (bus_id, estado);

-- RLS: mismo patrón city-scoped que chequeos_rapidos (vía bus_id -> buses.city).
alter table danos enable row level security;
create policy danos_select on danos for select to authenticated using (
  exists (select 1 from buses b where b.id = danos.bus_id and city_allowed(b.city)));
create policy danos_insert on danos for insert to authenticated with check (
  exists (select 1 from buses b where b.id = danos.bus_id and city_allowed(b.city)));
create policy danos_update on danos for update to authenticated using (
  exists (select 1 from buses b where b.id = danos.bus_id and city_allowed(b.city))
) with check (
  exists (select 1 from buses b where b.id = danos.bus_id and city_allowed(b.city)));
create policy danos_delete on danos for delete to authenticated using (
  jwt_role()='admin' and exists (select 1 from buses b where b.id = danos.bus_id and city_allowed(b.city)));
