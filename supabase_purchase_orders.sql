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
