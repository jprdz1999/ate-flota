-- Roles y ciudades por usuario (app_metadata) + RLS por ciudad.
-- Mismo modelo que el resto de este repo: no hay migrations tooling, esto ya
-- corrió a mano en el SQL editor de Supabase y se documenta aquí para historial.
--
-- Antes: user_metadata.city (editable por el propio usuario) mezclaba rol y
-- alcance de ciudad en un solo campo ('admin' = todo; cualquier otro valor =
-- lista de ciudades sin acceso a reportes/costos).
--
-- Ahora: dos claims independientes en app_metadata (solo editable vía Admin
-- API, no por el usuario):
--   role:   'admin' | 'user'
--   cities: 'all'   | lista de códigos de ciudad separados por coma
-- Un admin regional (role=admin, cities='gdl,tj') tiene los mismos permisos
-- que un admin global pero limitados a sus ciudades asignadas.

create or replace function public.jwt_role() returns text
language sql stable
set search_path = ''
as $$ select nullif(auth.jwt() -> 'app_metadata' ->> 'role', '') $$;

create or replace function public.jwt_cities() returns text
language sql stable
set search_path = ''
as $$ select nullif(auth.jwt() -> 'app_metadata' ->> 'cities', '') $$;

create or replace function public.city_allowed(target_city text) returns boolean
language sql stable
set search_path = ''
as $$
  select public.jwt_cities() = 'all'
      or target_city = any(string_to_array(public.jwt_cities(), ','))
$$;

-- buses: lectura/escritura de km,tires,open_issues,oil_interval para
-- cualquier usuario autenticado dentro de su alcance; alta/baja solo admin.
drop policy if exists allow_all_buses on buses;
create policy buses_select on buses for select to authenticated using (city_allowed(city));
create policy buses_insert on buses for insert to authenticated with check (jwt_role()='admin' and city_allowed(city));
create policy buses_update on buses for update to authenticated using (city_allowed(city)) with check (city_allowed(city));
create policy buses_delete on buses for delete to authenticated using (jwt_role()='admin' and city_allowed(city));

-- service_logs: cualquier usuario autenticado dentro de su alcance (sin update, la app no lo usa).
drop policy if exists allow_all_logs on service_logs;
create policy service_logs_select on service_logs for select to authenticated using (city_allowed(city));
create policy service_logs_insert on service_logs for insert to authenticated with check (city_allowed(city));
create policy service_logs_delete on service_logs for delete to authenticated using (city_allowed(city));

-- chequeos_rapidos: no tiene columna city propia, se resuelve vía bus_id -> buses.city.
drop policy if exists "authenticated full access" on chequeos_rapidos;
create policy chequeos_select on chequeos_rapidos for select to authenticated using (
  exists (select 1 from buses b where b.id = chequeos_rapidos.bus_id and city_allowed(b.city))
);
create policy chequeos_insert on chequeos_rapidos for insert to authenticated with check (
  exists (select 1 from buses b where b.id = chequeos_rapidos.bus_id and city_allowed(b.city))
);
create policy chequeos_update on chequeos_rapidos for update to authenticated using (
  exists (select 1 from buses b where b.id = chequeos_rapidos.bus_id and city_allowed(b.city))
) with check (
  exists (select 1 from buses b where b.id = chequeos_rapidos.bus_id and city_allowed(b.city))
);
create policy chequeos_delete on chequeos_rapidos for delete to authenticated using (
  jwt_role()='admin' and exists (select 1 from buses b where b.id = chequeos_rapidos.bus_id and city_allowed(b.city))
);

-- purchase_orders: mismo patrón, vía bus_id -> buses.city.
drop policy if exists "authenticated full access" on purchase_orders;
create policy po_select on purchase_orders for select to authenticated using (
  exists (select 1 from buses b where b.id = purchase_orders.bus_id and city_allowed(b.city))
);
create policy po_insert on purchase_orders for insert to authenticated with check (
  exists (select 1 from buses b where b.id = purchase_orders.bus_id and city_allowed(b.city))
);
create policy po_update on purchase_orders for update to authenticated using (
  exists (select 1 from buses b where b.id = purchase_orders.bus_id and city_allowed(b.city))
) with check (
  exists (select 1 from buses b where b.id = purchase_orders.bus_id and city_allowed(b.city))
);

-- operadores / operador_alias: catálogo compartido entre ciudades, sin scoping.
drop policy if exists "authenticated full access" on operadores;
create policy operadores_all on operadores for all to authenticated using (true) with check (true);

drop policy if exists "authenticated full access" on operador_alias;
create policy operador_alias_all on operador_alias for all to authenticated using (true) with check (true);

-- bases: catálogo de referencia, solo lectura desde la app.
drop policy if exists "authenticated full access" on bases;
create policy bases_select on bases for select to authenticated using (true);

-- Migración de los 3 usuarios existentes (user_metadata.city -> app_metadata role+cities):
--   jrd@autobusesate.com                -> role=admin, cities=all
--   guadalajara@autobusesate.com        -> role=user,  cities=gdl
--   emmanuel.bustamante@autobusesate.com -> role=user, cities=can,mer
