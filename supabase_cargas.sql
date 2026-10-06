-- Módulo Cargas (combustible) — Fase 1. Este repo no tiene migrations tooling;
-- se documenta aquí para historial. Aplicada vía el MCP de Supabase el 2026-10-06
-- (solo agrega: tabla nueva, columna nullable, trigger — no toca datos existentes).
--
-- Decisiones:
--   * El odómetro vivo sigue siendo buses.km (no se renombra a km_actual: lo
--     leen index.html, chequeo.html y su cola offline).
--   * Alcance por ciudad, igual que el resto de la app (city_allowed). No hay
--     supervisor por unidad todavía; supervisor_id es quién capturó la carga.
--   * Sin precios: solo litros.

-- ── Capacidad del tanque (litros) para la advertencia "exceso_litros" ─────────
alter table buses add column if not exists capacidad_tanque numeric
  check (capacidad_tanque is null or capacidad_tanque > 0);

-- ── Cargas ───────────────────────────────────────────────────────────────────
create table cargas (
  id             uuid primary key default gen_random_uuid(),
  bus_id         text not null references buses(id),
  supervisor_id  uuid not null default auth.uid(),   -- usuario que capturó
  usuario_email  text default (auth.jwt() ->> 'email'),
  fecha          date not null,
  litros         numeric(8,2) not null check (litros > 0),
  odometro       integer not null check (odometro >= 0),  -- lectura en ese momento
  tanque_lleno   boolean not null default true,
  foto_ticket    text,                                -- Fase 3 (storage path)
  flags          text[] not null default '{}',        -- km_menor | salto_km | exceso_litros | rendimiento_anomalo
  notas          text,
  created_at     timestamptz not null default now()
);
create index cargas_bus_fecha_idx on cargas (bus_id, fecha desc, odometro desc);
create index cargas_fecha_idx on cargas (fecha desc);

-- RLS: mismo patrón city-scoped que danos/chequeos_rapidos (vía bus_id -> buses.city).
-- Al insertar, supervisor_id tiene que ser el propio usuario.
alter table cargas enable row level security;
create policy cargas_select on cargas for select to authenticated using (
  exists (select 1 from buses b where b.id = cargas.bus_id and city_allowed(b.city)));
create policy cargas_insert on cargas for insert to authenticated with check (
  supervisor_id = auth.uid()
  and exists (select 1 from buses b where b.id = cargas.bus_id and city_allowed(b.city)));
create policy cargas_update on cargas for update to authenticated using (
  jwt_role()='admin' and exists (select 1 from buses b where b.id = cargas.bus_id and city_allowed(b.city))
) with check (
  jwt_role()='admin' and exists (select 1 from buses b where b.id = cargas.bus_id and city_allowed(b.city)));
create policy cargas_delete on cargas for delete to authenticated using (
  jwt_role()='admin' and exists (select 1 from buses b where b.id = cargas.bus_id and city_allowed(b.city)));

-- ── Odómetro: la carga lo avanza en la MISMA transacción ─────────────────────
-- Solo sube (una lectura vieja o una captura atrasada no lo baja). Corre como el
-- usuario que inserta: buses_update ya le permite su ciudad. Como el lote de
-- "Guardar todo" es un solo INSERT, o entran todas las cargas + odómetros o nada.
create or replace function cargas_bump_bus_km() returns trigger
language plpgsql set search_path = '' as $$
begin
  update public.buses set km = new.odometro
   where id = new.bus_id and (km is null or km < new.odometro);
  return new;
end $$;
create trigger cargas_bump_bus_km after insert on cargas
  for each row execute function cargas_bump_bus_km();


-- ═════════════════════════════════════════════════════════════════════════════
-- FASE 2 — DISEÑO DE CONSULTAS (no aplicado todavía)
-- ═════════════════════════════════════════════════════════════════════════════
--
-- Rendimiento (km/L), método tanque lleno a tanque lleno. Un segmento va de una
-- carga llena a la siguiente carga llena: km = diferencia de odómetros; litros =
-- TODO lo que entró después de la primera llena hasta la segunda inclusive (las
-- cargas parciales intermedias sí suman litros — si se descartaran, el km/L
-- saldría inflado). Las parciales no abren ni cierran segmento.
--
-- create view cargas_rendimiento with (security_invoker = true) as
-- with llenas as (
--   select id, bus_id, fecha, odometro,
--          lag(odometro) over (partition by bus_id order by odometro, created_at) as odo_ini
--   from cargas where tanque_lleno
-- )
-- select l.id as carga_id, l.bus_id, l.fecha,
--        l.odometro - l.odo_ini as km,
--        s.litros,
--        round((l.odometro - l.odo_ini) / nullif(s.litros, 0), 2) as km_l
-- from llenas l
-- cross join lateral (
--   select sum(c.litros) as litros from cargas c
--   where c.bus_id = l.bus_id and c.odometro > l.odo_ini and c.odometro <= l.odometro
-- ) s
-- where l.odo_ini is not null and l.odometro > l.odo_ini;
-- (La app hace este mismo cálculo en JS — rendimientoSegs() en index.html.)
--
-- Consumo por unidad / ciudad / mes (sin precios: litros):
--   select date_trunc('month', c.fecha)::date as mes, b.city, c.bus_id,
--          sum(c.litros) as litros, count(*) as cargas
--   from cargas c join buses b on b.id = c.bus_id
--   group by 1, 2, rollup(3);
--
-- Alertas de Inicio:
--   * "Sin carga en 10+ días": buses sin cargas con fecha >= current_date - 10.
--   * "Rendimiento cayó >20%": último km_l de cargas_rendimiento < 0.8 × promedio
--     de los 5 segmentos anteriores de la misma unidad.
--   * "Cargas con flags" (admins): select * from cargas where flags <> '{}'
--     order by fecha desc.
