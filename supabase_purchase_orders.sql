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
    'A/C','Compresor','Eléctrico','Frenos','Hojalatería y pintura','Llantas',
    'Mangueras/Conexiones','Mecánica general','Motor','Muelles/Amortiguadores',
    'Refacciones','Sistema de enfriamiento','Transmisión','Otro'
  ])
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2026-09-23: compras a stock.
-- Aplicado a Supabase. Una orden puede no tener unidad todavia: se captura
-- contra una ciudad y, ya pagada, queda pendiente de asignar en el Taller.
-- Al asignar se crean renglones hijos (uno por unidad, con su parte del monto,
-- parent_id apuntando al original) y el saldo del original baja; cuando llega a
-- cero queda 'asignada'. Lo que nunca corresponde a una unidad se cierra como
-- 'consumida' y sigue contando como gasto.
alter table purchase_orders alter column bus_id drop not null;
alter table purchase_orders add column if not exists city text;
alter table purchase_orders add column if not exists parent_id uuid references purchase_orders(id) on delete set null;
alter table purchase_orders add column if not exists stock_estado text;

alter table purchase_orders drop constraint if exists purchase_orders_stock_estado_check;
alter table purchase_orders add constraint purchase_orders_stock_estado_check check (
  stock_estado is null or stock_estado in ('pendiente','asignada','consumida')
);

-- O hay unidad, o hay ciudad: sin una de las dos el RLS no puede ubicar la fila
-- y quedaria invisible para todos, incluido quien la capturo.
alter table purchase_orders drop constraint if exists purchase_orders_destino_check;
alter table purchase_orders add constraint purchase_orders_destino_check check (
  bus_id is not null or city is not null
);

-- El monto sigue teniendo que ser positivo, salvo el saldo agotado de una
-- orden de stock ya repartida por completo.
alter table purchase_orders drop constraint if exists purchase_orders_monto_check;
alter table purchase_orders add constraint purchase_orders_monto_check check (
  monto > 0 or (bus_id is null and stock_estado = 'asignada')
);

-- RLS: las tres politicas ubicaban la orden SOLO por su unidad. Ahora se ubica
-- por unidad o, si no hay, por ciudad. El modelo de alcance no cambia: sigue
-- siendo city_allowed.
drop policy if exists po_select on purchase_orders;
create policy po_select on purchase_orders for select to authenticated
using (case when bus_id is null then city_allowed(city)
            else exists (select 1 from buses b where b.id = bus_id and city_allowed(b.city)) end);

drop policy if exists po_insert on purchase_orders;
create policy po_insert on purchase_orders for insert to authenticated
with check (case when bus_id is null then city_allowed(city)
                 else exists (select 1 from buses b where b.id = bus_id and city_allowed(b.city)) end);

drop policy if exists po_update on purchase_orders;
create policy po_update on purchase_orders for update to authenticated
using (case when bus_id is null then city_allowed(city)
            else exists (select 1 from buses b where b.id = bus_id and city_allowed(b.city)) end)
with check (case when bus_id is null then city_allowed(city)
                 else exists (select 1 from buses b where b.id = bus_id and city_allowed(b.city)) end);
