-- Órdenes de Compra de Taller — esquema para correr a mano en el SQL editor de
-- Supabase. Mismo modelo que supabase_mini_checkups.sql: este repo no tiene
-- migrations tooling, la tabla vive directo en el proyecto de Supabase.

create table purchase_orders (
  id uuid primary key default gen_random_uuid(),
  folio_num int generated always as identity,
  folio text generated always as ('PO-' || lpad(folio_num::text, 4, '0')) stored,
  created_at timestamptz not null default now(),
  bus_id text not null references buses(id),
  tipo_servicio text not null check (tipo_servicio in (
    'Mecánica general','Llantas','Eléctrico','Hojalatería y pintura','Refacciones','Otro'
  )),
  concepto text not null,
  proveedor text not null,
  cuenta_referencia text,
  monto numeric(10,2) not null check (monto > 0),
  solicita text not null,
  base_id text references bases(id),
  status text not null default 'pendiente' check (status in (
    'pendiente','autorizada','pagada','rechazada'
  ))
);

-- RLS: mismo modelo permisivo (autenticado = acceso completo) que ya usa el
-- resto de la app (ver supabase_mini_checkups.sql).
alter table purchase_orders enable row level security;
create policy "authenticated full access" on purchase_orders for all to authenticated using (true) with check (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2026-09-23: banco del proveedor.
-- Aplicado a Supabase. Texto libre con sugerencias en la UI (Santander, BBVA,
-- Banorte...): la lista de bancos cambia y no justifica un enum ni una tabla
-- catalogo. Nullable, igual que cuenta_referencia — las ordenes ya capturadas
-- no lo traen y el campo es opcional.
-- La pagina lo autocompleta desde el ultimo banco usado con ese proveedor,
-- misma "memoria de proveedores" que ya alimenta la cuenta/referencia; no hay
-- tabla de proveedores, la fuente de verdad son las ordenes capturadas.
alter table purchase_orders add column if not exists banco text;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2026-09-23: el CHECK de tipo_servicio se quedo atras.
-- Aplicado a Supabase. Al unificar el vocabulario de tipos (SERVICE_TYPES en
-- index.html, 13 opciones compartidas entre ordenes de compra y reparaciones)
-- solo se cambio el front: el CHECK seguia aceptando las 6 opciones originales,
-- asi que elegir Compresor/Frenos/Motor/Transmision/Mangueras/Muelles/
-- Enfriamiento hacia fallar el insert en produccion.
-- Los 6 valores viejos siguen en la lista, asi que no se invalida nada de lo
-- ya capturado. Si vuelve a cambiar SERVICE_TYPES, este CHECK se mueve con el.
alter table purchase_orders drop constraint if exists purchase_orders_tipo_servicio_check;
alter table purchase_orders add constraint purchase_orders_tipo_servicio_check check (
  tipo_servicio = any (array[
    'Compresor','Eléctrico','Frenos','Hojalatería y pintura','Llantas',
    'Mangueras/Conexiones','Mecánica general','Motor','Muelles/Amortiguadores',
    'Refacciones','Sistema de enfriamiento','Transmisión','Otro'
  ])
);
