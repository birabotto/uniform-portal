
begin;

create extension if not exists pgcrypto;

drop schema if exists public cascade;
create schema public;
grant usage on schema public to postgres, anon, authenticated, service_role;
grant create on schema public to postgres, service_role;
create extension if not exists pgcrypto with schema public;

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  employee_id text not null unique,
  full_name text not null,
  ikea_email text not null unique,
  department text,
  job_title text,
  location text not null default 'Toronto',
  size_top text,
  size_bottom text,
  is_active boolean not null default true,
  imported_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.employee_import_runs (
  id uuid primary key default gen_random_uuid(),
  source_name text not null default 'manual import',
  imported_count integer not null default 0,
  payload jsonb not null default '[]'::jsonb,
  imported_by uuid,
  created_at timestamptz not null default now()
);

create table public.uniform_size_chart (
  id uuid primary key default gen_random_uuid(),
  category text not null,
  size_label text not null,
  chest_range text,
  waist_range text,
  hip_range text,
  fit_note text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (category, size_label)
);

create table public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique,
  product_type text not null,
  layer text,
  colour text not null default 'Standard',
  fit text,
  sleeve text,
  style text not null,
  size text not null,
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  reserved_quantity integer not null default 0 check (reserved_quantity >= 0),
  ordered_quantity integer not null default 0 check (ordered_quantity >= 0),
  dry_cleaned_quantity integer not null default 0 check (dry_cleaned_quantity >= 0),
  reorder_level integer not null default 2 check (reorder_level >= 0),
  unit text not null default 'pcs',
  is_active boolean not null default true,
  location text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint inventory_reserved_le_stock check (reserved_quantity <= stock_quantity)
);

create table public.inventory_stock_movements (
  id uuid primary key default gen_random_uuid(),
  inventory_item_id uuid not null references public.inventory_items(id) on delete cascade,
  qty_delta integer not null check (qty_delta <> 0),
  movement_type text not null check (
    movement_type in ('seed', 'restock', 'adjustment', 'reservation', 'reservation_release', 'fulfillment', 'manual_correction')
  ),
  reason text,
  related_request_id uuid,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table public.uniform_requests (
  id uuid primary key default gen_random_uuid(),
  request_number bigint generated always as identity unique,
  created_by uuid,
  employee_record_id uuid not null references public.employees(id) on delete restrict,
  employee_id text not null,
  employee_name text not null,
  employee_email text not null,
  employee_department text,
  fulfillment_mode text not null default 'pending_decision'
    check (fulfillment_mode in ('in_stock', 'size_up', 'special_request', 'pending_decision')),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'ordered', 'fulfilled', 'rejected', 'cancelled')),
  notes text,
  admin_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.request_items (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.uniform_requests(id) on delete cascade,
  inventory_item_id uuid references public.inventory_items(id) on delete set null,
  reserved_item_id uuid references public.inventory_items(id) on delete set null,
  product_type text not null,
  layer text,
  colour text not null,
  fit text,
  sleeve text,
  style text not null,
  requested_size text not null,
  suggested_size text,
  quantity integer not null default 1 check (quantity > 0),
  line_status text not null default 'pending'
    check (line_status in ('pending', 'reserved', 'approved', 'ordered', 'fulfilled', 'rejected', 'cancelled')),
  created_at timestamptz not null default now()
);

create table public.request_history (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.uniform_requests(id) on delete cascade,
  action text not null,
  old_status text,
  new_status text,
  message text,
  changed_by uuid,
  created_at timestamptz not null default now()
);

create index idx_employees_active on public.employees(is_active);
create index idx_employees_department on public.employees(department);
create index idx_inventory_lookup on public.inventory_items(product_type, fit, size);
create index idx_uniform_requests_status on public.uniform_requests(status, created_at desc);
create index idx_request_items_request_id on public.request_items(request_id);
create index idx_request_history_request_id on public.request_history(request_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.size_rank(p_size text)
returns integer
language sql
immutable
as $$
  select case upper(coalesce(trim(p_size), ''))
    when 'CD' then 1
    when 'EF' then 2
    when 'GH' then 3
    when 'IJ' then 4
    when 'KN' then 5
    when 'OP' then 6
    when 'QR' then 7
    when 'TU' then 8
    when 'VY' then 9
    when 'C' then 10
    when 'D' then 11
    when 'E' then 12
    when 'F' then 13
    when 'G' then 14
    when 'H' then 15
    when 'I' then 16
    when 'J' then 17
    when 'K' then 18
    when 'N' then 19
    when 'O' then 20
    when 'P' then 21
    when 'Q' then 22
    when 'R' then 23
    when 'T' then 24
    when 'U' then 25
    when 'V' then 26
    when 'Y' then 27
    when 'ONE SIZE' then 99
    else 999
  end;
$$;

create trigger trg_employees_updated_at
before update on public.employees
for each row execute procedure public.set_updated_at();

create trigger trg_inventory_items_updated_at
before update on public.inventory_items
for each row execute procedure public.set_updated_at();

create trigger trg_uniform_requests_updated_at
before update on public.uniform_requests
for each row execute procedure public.set_updated_at();

create or replace function public.lookup_employee_by_id(p_employee_id text)
returns public.employees
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee public.employees%rowtype;
begin
  select *
    into v_employee
    from public.employees
   where employee_id = trim(p_employee_id)
     and is_active = true
   limit 1;

  return v_employee;
end;
$$;

create or replace function public.reserve_inventory(p_inventory_item_id uuid, p_qty integer default 1)
returns public.inventory_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.inventory_items%rowtype;
begin
  if p_qty <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  update public.inventory_items
     set reserved_quantity = reserved_quantity + p_qty
   where id = p_inventory_item_id
     and (stock_quantity - reserved_quantity) >= p_qty
  returning * into v_item;

  if not found then
    raise exception 'Not enough available stock to reserve';
  end if;

  insert into public.inventory_stock_movements (inventory_item_id, qty_delta, movement_type, reason, created_by)
  values (p_inventory_item_id, p_qty, 'reservation', 'Reserved from request submit', auth.uid());

  return v_item;
end;
$$;

create or replace function public.release_inventory(p_inventory_item_id uuid, p_qty integer default 1)
returns public.inventory_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.inventory_items%rowtype;
begin
  if p_qty <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  update public.inventory_items
     set reserved_quantity = greatest(reserved_quantity - p_qty, 0)
   where id = p_inventory_item_id
  returning * into v_item;

  if not found then
    raise exception 'Inventory item not found';
  end if;

  insert into public.inventory_stock_movements (inventory_item_id, qty_delta, movement_type, reason, created_by)
  values (p_inventory_item_id, -p_qty, 'reservation_release', 'Released reservation', auth.uid());

  return v_item;
end;
$$;

create or replace function public.add_stock(p_item_id uuid, p_amount integer)
returns public.inventory_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.inventory_items%rowtype;
begin
  if coalesce(p_amount, 0) <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;

  update public.inventory_items
     set stock_quantity = stock_quantity + p_amount
   where id = p_item_id
   returning * into v_item;

  if not found then
    raise exception 'Inventory item not found';
  end if;

  insert into public.inventory_stock_movements (inventory_item_id, qty_delta, movement_type, reason, created_by)
  values (p_item_id, p_amount, 'restock', 'Stock added from dashboard', auth.uid());

  return v_item;
end;
$$;

create or replace function public.submit_uniform_request(
  p_employee_id text,
  p_inventory_item_id uuid,
  p_notes text default null,
  p_quantity integer default 1
)
returns public.uniform_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee public.employees%rowtype;
  v_item public.inventory_items%rowtype;
  v_size_up public.inventory_items%rowtype;
  v_request public.uniform_requests%rowtype;
  v_mode text := 'special_request';
begin
  if p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  select * into v_employee
    from public.employees
   where employee_id = trim(p_employee_id)
     and is_active = true
   limit 1;

  if not found then
    raise exception 'Employee ID not found in employees table';
  end if;

  select * into v_item
    from public.inventory_items
   where id = p_inventory_item_id
     and is_active = true
   for update;

  if not found then
    raise exception 'Inventory item not found';
  end if;

  if (v_item.stock_quantity - v_item.reserved_quantity) >= p_quantity then
    perform public.reserve_inventory(v_item.id, p_quantity);
    v_mode := 'in_stock';
  else
    select * into v_size_up
      from public.inventory_items
     where is_active = true
       and product_type = v_item.product_type
       and coalesce(fit, '') = coalesce(v_item.fit, '')
       and public.size_rank(size) > public.size_rank(v_item.size)
       and (stock_quantity - reserved_quantity) >= p_quantity
     order by public.size_rank(size)
     limit 1
     for update;

    if found then
      perform public.reserve_inventory(v_size_up.id, p_quantity);
      v_mode := 'size_up';
    end if;
  end if;

  insert into public.uniform_requests (
    employee_record_id,
    employee_id,
    employee_name,
    employee_email,
    employee_department,
    fulfillment_mode,
    status,
    notes
  ) values (
    v_employee.id,
    v_employee.employee_id,
    v_employee.full_name,
    v_employee.ikea_email,
    v_employee.department,
    v_mode,
    'pending',
    p_notes
  )
  returning * into v_request;

  insert into public.request_items (
    request_id,
    inventory_item_id,
    reserved_item_id,
    product_type,
    layer,
    colour,
    fit,
    sleeve,
    style,
    requested_size,
    suggested_size,
    quantity,
    line_status
  ) values (
    v_request.id,
    v_item.id,
    case when v_mode = 'in_stock' then v_item.id when v_mode = 'size_up' then v_size_up.id else null end,
    v_item.product_type,
    v_item.layer,
    v_item.colour,
    v_item.fit,
    v_item.sleeve,
    v_item.style,
    v_item.size,
    case when v_mode = 'size_up' then v_size_up.size else null end,
    p_quantity,
    case when v_mode in ('in_stock', 'size_up') then 'reserved' else 'pending' end
  );

  insert into public.request_history (request_id, action, old_status, new_status, message, changed_by)
  values (
    v_request.id,
    'created',
    null,
    'pending',
    case
      when v_mode = 'in_stock' then 'Request created. Requested size reserved from stock.'
      when v_mode = 'size_up' then 'Requested size unavailable. Next available size up reserved.'
      else 'No stock available. Request marked as special request.'
    end,
    auth.uid()
  );

  return v_request;
end;
$$;

create or replace function public.set_request_status(
  p_request_id uuid,
  p_new_status text,
  p_message text default null,
  p_changed_by uuid default auth.uid()
)
returns public.uniform_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.uniform_requests%rowtype;
  v_old_status text;
  v_line record;
begin
  if p_new_status not in ('pending', 'approved', 'ordered', 'fulfilled', 'rejected', 'cancelled') then
    raise exception 'Invalid status';
  end if;

  select *
    into v_request
    from public.uniform_requests
   where id = p_request_id
   for update;

  if not found then
    raise exception 'Request not found';
  end if;

  v_old_status := v_request.status;

  if p_new_status in ('rejected', 'cancelled') and v_old_status not in ('rejected', 'cancelled', 'fulfilled') then
    for v_line in
      select * from public.request_items where request_id = p_request_id and reserved_item_id is not null
    loop
      update public.inventory_items
         set reserved_quantity = greatest(reserved_quantity - v_line.quantity, 0)
       where id = v_line.reserved_item_id;

      insert into public.inventory_stock_movements (
        inventory_item_id, qty_delta, movement_type, reason, related_request_id, created_by
      ) values (
        v_line.reserved_item_id, -v_line.quantity, 'reservation_release',
        coalesce(p_message, 'Reservation released after request status change'),
        p_request_id, p_changed_by
      );
    end loop;
  end if;

  if p_new_status = 'fulfilled' and v_old_status <> 'fulfilled' then
    for v_line in
      select * from public.request_items where request_id = p_request_id and reserved_item_id is not null
    loop
      update public.inventory_items
         set stock_quantity = greatest(stock_quantity - v_line.quantity, 0),
             reserved_quantity = greatest(reserved_quantity - v_line.quantity, 0)
       where id = v_line.reserved_item_id;

      insert into public.inventory_stock_movements (
        inventory_item_id, qty_delta, movement_type, reason, related_request_id, created_by
      ) values (
        v_line.reserved_item_id, -v_line.quantity, 'fulfillment',
        coalesce(p_message, 'Stock fulfilled for request'),
        p_request_id, p_changed_by
      );
    end loop;
  end if;

  update public.request_items
     set line_status = case
       when p_new_status = 'approved' then 'approved'
       when p_new_status = 'ordered' then 'ordered'
       when p_new_status = 'fulfilled' then 'fulfilled'
       when p_new_status = 'rejected' then 'rejected'
       when p_new_status = 'cancelled' then 'cancelled'
       else line_status
     end
   where request_id = p_request_id;

  update public.uniform_requests
     set status = p_new_status,
         admin_notes = case when p_message is not null and btrim(p_message) <> '' then p_message else admin_notes end
   where id = p_request_id
   returning * into v_request;

  insert into public.request_history (request_id, action, old_status, new_status, message, changed_by)
  values (p_request_id, 'status_changed', v_old_status, p_new_status, p_message, p_changed_by);

  return v_request;
end;
$$;

create or replace function public.import_employees_from_json(p_payload jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_count integer := 0;
begin
  for v_item in select * from jsonb_array_elements(coalesce(p_payload, '[]'::jsonb))
  loop
    insert into public.employees (
      employee_id, full_name, ikea_email, department, location, is_active, imported_at
    ) values (
      trim(v_item ->> 'employee_id'),
      trim(v_item ->> 'full_name'),
      lower(trim(v_item ->> 'ikea_email')),
      nullif(trim(v_item ->> 'department'), ''),
      coalesce(nullif(trim(v_item ->> 'location'), ''), 'Toronto'),
      coalesce((v_item ->> 'is_active')::boolean, true),
      now()
    )
    on conflict (employee_id) do update
      set full_name = excluded.full_name,
          ikea_email = excluded.ikea_email,
          department = excluded.department,
          location = excluded.location,
          is_active = excluded.is_active,
          imported_at = now();

    v_count := v_count + 1;
  end loop;

  insert into public.employee_import_runs (source_name, imported_count, payload, imported_by)
  values ('json import', v_count, coalesce(p_payload, '[]'::jsonb), auth.uid());

  return v_count;
end;
$$;

create or replace view public.v_inventory_available as
select
  i.*,
  greatest(i.stock_quantity - i.reserved_quantity, 0) as available_quantity,
  case when greatest(i.stock_quantity - i.reserved_quantity, 0) <= i.reorder_level then true else false end as is_low_stock
from public.inventory_items i;

create or replace view public.v_request_analytics as
select
  ri.product_type,
  ri.fit,
  ri.requested_size,
  ri.requested_size as size,
  concat_ws(' · ', ri.product_type, ri.fit, ri.requested_size) as item_label,
  sum(ri.quantity) as total_qty,
  count(*) as line_count,
  sum(case when ur.status in ('approved', 'ordered', 'fulfilled') then ri.quantity else 0 end) as progressed_count
from public.request_items ri
join public.uniform_requests ur on ur.id = ri.request_id
group by ri.product_type, ri.fit, ri.requested_size;

grant usage on schema public to anon, authenticated;
grant select on public.inventory_items to anon;
grant select on public.uniform_size_chart to anon;
grant select on public.v_inventory_available to anon;

grant select, insert, update, delete on public.employees to authenticated;
grant select, insert, update, delete on public.employee_import_runs to authenticated;
grant select, insert, update, delete on public.uniform_size_chart to authenticated;
grant select, insert, update, delete on public.inventory_items to authenticated;
grant select, insert, update, delete on public.inventory_stock_movements to authenticated;
grant select, insert, update, delete on public.uniform_requests to authenticated;
grant select, insert, update, delete on public.request_items to authenticated;
grant select, insert, update, delete on public.request_history to authenticated;
grant select on public.v_inventory_available to authenticated;
grant select on public.v_request_analytics to authenticated;

grant execute on function public.lookup_employee_by_id(text) to anon, authenticated;
grant execute on function public.reserve_inventory(uuid, integer) to authenticated;
grant execute on function public.release_inventory(uuid, integer) to authenticated;
grant execute on function public.add_stock(uuid, integer) to authenticated;
grant execute on function public.submit_uniform_request(text, uuid, text, integer) to anon, authenticated;
grant execute on function public.set_request_status(uuid, text, text, uuid) to authenticated;
grant execute on function public.import_employees_from_json(jsonb) to authenticated;

alter table public.employees enable row level security;
alter table public.employee_import_runs enable row level security;
alter table public.uniform_size_chart enable row level security;
alter table public.inventory_items enable row level security;
alter table public.inventory_stock_movements enable row level security;
alter table public.uniform_requests enable row level security;
alter table public.request_items enable row level security;
alter table public.request_history enable row level security;

create policy employees_authenticated_all on public.employees for all to authenticated using (true) with check (true);
create policy employee_import_runs_authenticated_all on public.employee_import_runs for all to authenticated using (true) with check (true);
create policy size_chart_authenticated_all on public.uniform_size_chart for all to authenticated using (true) with check (true);
create policy inventory_authenticated_all on public.inventory_items for all to authenticated using (true) with check (true);
create policy stock_movements_authenticated_all on public.inventory_stock_movements for all to authenticated using (true) with check (true);
create policy requests_authenticated_all on public.uniform_requests for all to authenticated using (true) with check (true);
create policy request_items_authenticated_all on public.request_items for all to authenticated using (true) with check (true);
create policy request_history_authenticated_all on public.request_history for all to authenticated using (true) with check (true);

create policy inventory_anon_read on public.inventory_items for select to anon using (is_active = true);
create policy size_chart_anon_read on public.uniform_size_chart for select to anon using (true);

insert into public.uniform_size_chart (
  category, size_label, chest_range, waist_range, hip_range, fit_note, sort_order
) values
  ('shaped_tops', 'CD', '26.75-28.25 in', null, null, 'Shaped tops from IKEA size chart PDF', 1),
  ('shaped_tops', 'EF', '30-31.5 in', null, null, 'Shaped tops from IKEA size chart PDF', 2),
  ('shaped_tops', 'GH', '33-34.5 in', null, null, 'Shaped tops from IKEA size chart PDF', 3),
  ('shaped_tops', 'IJ', '36.25-37.75 in', null, null, 'Shaped tops from IKEA size chart PDF', 4),
  ('shaped_tops', 'KN', '39.5-41 in', null, null, 'Shaped tops from IKEA size chart PDF', 5),
  ('shaped_tops', 'OP', '43.25-45.75 in', null, null, 'Shaped tops from IKEA size chart PDF', 6),
  ('shaped_tops', 'QR', '48-50.5 in', null, null, 'Shaped tops from IKEA size chart PDF', 7),
  ('shaped_tops', 'TU', '53.5-56.75 in', null, null, 'Shaped tops from IKEA size chart PDF', 8),
  ('shaped_tops', 'VY', '60-63 in', null, null, 'Shaped tops from IKEA size chart PDF', 9),
  ('straight_tops', 'CD', '31.5-33 in', null, null, 'Straight tops from IKEA size chart PDF', 1),
  ('straight_tops', 'EF', '34.5-36.25 in', null, null, 'Straight tops from IKEA size chart PDF', 2),
  ('straight_tops', 'GH', '37.75-39.5 in', null, null, 'Straight tops from IKEA size chart PDF', 3),
  ('straight_tops', 'IJ', '41-42.5 in', null, null, 'Straight tops from IKEA size chart PDF', 4),
  ('straight_tops', 'KN', '44-45.75 in', null, null, 'Straight tops from IKEA size chart PDF', 5),
  ('straight_tops', 'OP', '48-50.5 in', null, null, 'Straight tops from IKEA size chart PDF', 6),
  ('straight_tops', 'QR', '52.75-55 in', null, null, 'Straight tops from IKEA size chart PDF', 7),
  ('straight_tops', 'TU', '58.25-61.5 in', null, null, 'Straight tops from IKEA size chart PDF', 8),
  ('straight_tops', 'VY', '64.5-67.75 in', null, null, 'Straight tops from IKEA size chart PDF', 9),
  ('shaped_bottoms', 'C', null, '20.5 in', '30 in', 'Measure waist and low hip; choose the biggest measurement', 1),
  ('shaped_bottoms', 'D', null, '22 in', '31.5 in', 'Measure waist and low hip; choose the biggest measurement', 2),
  ('shaped_bottoms', 'E', null, '23.5 in', '33 in', 'Measure waist and low hip; choose the biggest measurement', 3),
  ('shaped_bottoms', 'F', null, '25.25 in', '34.5 in', 'Measure waist and low hip; choose the biggest measurement', 4),
  ('shaped_bottoms', 'G', null, '26.75 in', '36.25 in', 'Measure waist and low hip; choose the biggest measurement', 5),
  ('shaped_bottoms', 'H', null, '28.25 in', '37.75 in', 'Measure waist and low hip; choose the biggest measurement', 6),
  ('shaped_bottoms', 'I', null, '30 in', '39.5 in', 'Measure waist and low hip; choose the biggest measurement', 7),
  ('shaped_bottoms', 'J', null, '31.5 in', '41 in', 'Measure waist and low hip; choose the biggest measurement', 8),
  ('shaped_bottoms', 'K', null, '33 in', '42.5 in', 'Measure waist and low hip; choose the biggest measurement', 9),
  ('shaped_bottoms', 'N', null, '34.5 in', '44 in', 'Measure waist and low hip; choose the biggest measurement', 10),
  ('shaped_bottoms', 'O', null, '37 in', '46.5 in', 'Measure waist and low hip; choose the biggest measurement', 11),
  ('shaped_bottoms', 'P', null, '39.5 in', '48.75 in', 'Measure waist and low hip; choose the biggest measurement', 12),
  ('shaped_bottoms', 'Q', null, '41.75 in', '51.25 in', 'Measure waist and low hip; choose the biggest measurement', 13),
  ('shaped_bottoms', 'R', null, '44 in', '53.5 in', 'Measure waist and low hip; choose the biggest measurement', 14),
  ('shaped_bottoms', 'T', null, '47.25 in', '56.75 in', 'Measure waist and low hip; choose the biggest measurement', 15),
  ('shaped_bottoms', 'U', null, '50.5 in', '60 in', 'Measure waist and low hip; choose the biggest measurement', 16),
  ('shaped_bottoms', 'V', null, '53.5 in', '63 in', 'Measure waist and low hip; choose the biggest measurement', 17),
  ('shaped_bottoms', 'Y', null, '56.75 in', '66.25 in', 'Measure waist and low hip; choose the biggest measurement', 18),
  ('straight_bottoms', 'C', null, '26.75 in', null, 'Straight bottoms use waist measurement', 1),
  ('straight_bottoms', 'D', null, '28.25 in', null, 'Straight bottoms use waist measurement', 2),
  ('straight_bottoms', 'E', null, '30 in', null, 'Straight bottoms use waist measurement', 3),
  ('straight_bottoms', 'F', null, '31.5 in', null, 'Straight bottoms use waist measurement', 4),
  ('straight_bottoms', 'G', null, '33 in', null, 'Straight bottoms use waist measurement', 5),
  ('straight_bottoms', 'H', null, '34.5 in', null, 'Straight bottoms use waist measurement', 6),
  ('straight_bottoms', 'I', null, '36.25 in', null, 'Straight bottoms use waist measurement', 7),
  ('straight_bottoms', 'J', null, '37.75 in', null, 'Straight bottoms use waist measurement', 8),
  ('straight_bottoms', 'K', null, '39.5 in', null, 'Straight bottoms use waist measurement', 9),
  ('straight_bottoms', 'N', null, '41 in', null, 'Straight bottoms use waist measurement', 10),
  ('straight_bottoms', 'O', null, '43.25 in', null, 'Straight bottoms use waist measurement', 11),
  ('straight_bottoms', 'P', null, '45.75 in', null, 'Straight bottoms use waist measurement', 12),
  ('straight_bottoms', 'Q', null, '48 in', null, 'Straight bottoms use waist measurement', 13),
  ('straight_bottoms', 'R', null, '50.5 in', null, 'Straight bottoms use waist measurement', 14),
  ('straight_bottoms', 'T', null, '53.5 in', null, 'Straight bottoms use waist measurement', 15),
  ('straight_bottoms', 'U', null, '56.75 in', null, 'Straight bottoms use waist measurement', 16),
  ('straight_bottoms', 'V', null, '60 in', null, 'Straight bottoms use waist measurement', 17),
  ('straight_bottoms', 'Y', null, '63 in', null, 'Straight bottoms use waist measurement', 18),
  ('shaped_tops_single', 'C', null, null, null, 'Single-size top reference', 1),
  ('straight_tops_single', 'C', null, null, null, 'Single-size top reference', 1),
  ('shaped_tops_single', 'D', null, null, null, 'Single-size top reference', 2),
  ('straight_tops_single', 'D', null, null, null, 'Single-size top reference', 2),
  ('shaped_tops_single', 'E', null, null, null, 'Single-size top reference', 3),
  ('straight_tops_single', 'E', null, null, null, 'Single-size top reference', 3),
  ('shaped_tops_single', 'F', null, null, null, 'Single-size top reference', 4),
  ('straight_tops_single', 'F', null, null, null, 'Single-size top reference', 4),
  ('shaped_tops_single', 'G', null, null, null, 'Single-size top reference', 5),
  ('straight_tops_single', 'G', null, null, null, 'Single-size top reference', 5),
  ('shaped_tops_single', 'H', null, null, null, 'Single-size top reference', 6),
  ('straight_tops_single', 'H', null, null, null, 'Single-size top reference', 6),
  ('shaped_tops_single', 'I', null, null, null, 'Single-size top reference', 7),
  ('straight_tops_single', 'I', null, null, null, 'Single-size top reference', 7),
  ('shaped_tops_single', 'J', null, null, null, 'Single-size top reference', 8),
  ('straight_tops_single', 'J', null, null, null, 'Single-size top reference', 8),
  ('shaped_tops_single', 'K', null, null, null, 'Single-size top reference', 9),
  ('straight_tops_single', 'K', null, null, null, 'Single-size top reference', 9),
  ('shaped_tops_single', 'N', null, null, null, 'Single-size top reference', 10),
  ('straight_tops_single', 'N', null, null, null, 'Single-size top reference', 10),
  ('shaped_tops_single', 'O', null, null, null, 'Single-size top reference', 11),
  ('straight_tops_single', 'O', null, null, null, 'Single-size top reference', 11),
  ('shaped_tops_single', 'P', null, null, null, 'Single-size top reference', 12),
  ('straight_tops_single', 'P', null, null, null, 'Single-size top reference', 12),
  ('shaped_tops_single', 'Q', null, null, null, 'Single-size top reference', 13),
  ('straight_tops_single', 'Q', null, null, null, 'Single-size top reference', 13),
  ('shaped_tops_single', 'R', null, null, null, 'Single-size top reference', 14),
  ('straight_tops_single', 'R', null, null, null, 'Single-size top reference', 14),
  ('shaped_tops_single', 'T', null, null, null, 'Single-size top reference', 15),
  ('straight_tops_single', 'T', null, null, null, 'Single-size top reference', 15),
  ('shaped_tops_single', 'U', null, null, null, 'Single-size top reference', 16),
  ('straight_tops_single', 'U', null, null, null, 'Single-size top reference', 16),
  ('shaped_tops_single', 'V', null, null, null, 'Single-size top reference', 17),
  ('straight_tops_single', 'V', null, null, null, 'Single-size top reference', 17),
  ('shaped_tops_single', 'Y', null, null, null, 'Single-size top reference', 18),
  ('straight_tops_single', 'Y', null, null, null, 'Single-size top reference', 18),
  ('accessories', 'ONE SIZE', null, null, null, 'Beanie and many accessories use one size', 1),
  ('accessories', 'C-J', null, null, null, 'Apron size range C-J', 2),
  ('accessories', 'K-Y', null, null, null, 'Apron size range K-Y', 3);

insert into public.employees (
  employee_id, full_name, ikea_email, department, job_title, location, size_top, size_bottom, imported_at
) values
  ('100001', 'Amanda Silva', 'amanda.silva@ikea.com', 'Fulfillment Operations', 'Co-worker', 'Toronto', 'GH', 'J', now()),
  ('100002', 'Denis Costa', 'denis.costa@ikea.com', 'Fulfillment Operations', 'Co-worker', 'Toronto', 'IJ', 'K', now()),
  ('100003', 'Dayana Rocha', 'dayana.rocha@ikea.com', 'Customer Service', 'Co-worker', 'Toronto', 'EF', 'H', now()),
  ('100004', 'Andrew Plumer', 'andrew.plumer@ikea.com', 'IKEA Food', 'Co-worker', 'Toronto', 'KN', 'N', now());

insert into public.inventory_items (
  sku, product_type, layer, colour, fit, sleeve, style, size,
  stock_quantity, reserved_quantity, ordered_quantity, dry_cleaned_quantity, reorder_level, location, notes
) values
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-C', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'C', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-D', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'D', 5, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-E', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'E', 10, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-F', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'F', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-G', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'G', 7, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-H', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'H', 13, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-I', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'I', 8, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-J', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'J', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-K', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'K', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-N', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'N', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-O', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'O', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-P', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'P', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-Q', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'Q', 7, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-R', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'R', 6, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-T', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'T', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-U', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'U', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-V', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'V', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-SHAPED-Y', '4-Pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, '4-Pocket Pants', 'Y', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-C', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'C', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-D', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'D', 13, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-E', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'E', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-F', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'F', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-G', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'G', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-H', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'H', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-I', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'I', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-J', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'J', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-K', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'K', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-N', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'N', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-O', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'O', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-P', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'P', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-Q', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'Q', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-R', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'R', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-T', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'T', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-U', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'U', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-V', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'V', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-4-POCKET-PANTS-STRAIGHT-Y', '4-Pocket Pants', 'Bottoms', 'Standard', 'Straight', null, '4-Pocket Pants', 'Y', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-C', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'C', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-D', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'D', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-E', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'E', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-F', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'F', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-G', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'G', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-H', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'H', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-I', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'I', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-J', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'J', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-K', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'K', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-N', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'N', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-O', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'O', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-P', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'P', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-Q', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'Q', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-R', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'R', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-T', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'T', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-U', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'U', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-V', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'V', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-SHAPED-Y', 'Kitchen Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Kitchen Pants', 'Y', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-C', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'C', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-D', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'D', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-E', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'E', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-F', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'F', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-G', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'G', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-H', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'H', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-I', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'I', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-J', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'J', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-K', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'K', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-N', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'N', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-O', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'O', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-P', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'P', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-Q', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'Q', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-R', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'R', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-T', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'T', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-U', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'U', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-V', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'V', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-KITCHEN-PANTS-STRAIGHT-Y', 'Kitchen Pants', 'Bottoms', 'Standard', 'Straight', null, 'Kitchen Pants', 'Y', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-C', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'C', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-D', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'D', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-E', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'E', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-F', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'F', 5, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-G', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'G', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-H', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'H', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-I', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'I', 7, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-J', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'J', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-K', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'K', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-N', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'N', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-O', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'O', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-P', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'P', 5, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-Q', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'Q', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-R', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'R', 9, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-T', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'T', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-U', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'U', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-V', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'V', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-SHAPED-Y', 'Lightweight Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Lightweight Pants', 'Y', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-C', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'C', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-D', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'D', 10, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-E', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'E', 11, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-F', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'F', 7, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-G', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'G', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-H', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'H', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-I', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'I', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-J', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'J', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-K', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'K', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-N', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'N', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-O', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'O', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-P', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'P', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-Q', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'Q', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-R', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'R', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-T', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'T', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-U', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'U', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-V', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'V', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LIGHTWEIGHT-PANTS-STRAIGHT-Y', 'Lightweight Pants', 'Bottoms', 'Standard', 'Straight', null, 'Lightweight Pants', 'Y', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LONG-SKIRTS-D', 'Long Skirts', 'Bottoms', 'Standard', null, null, 'Long Skirts', 'D', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LONG-SKIRTS-F', 'Long Skirts', 'Bottoms', 'Standard', null, null, 'Long Skirts', 'F', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LONG-SKIRTS-H', 'Long Skirts', 'Bottoms', 'Standard', null, null, 'Long Skirts', 'H', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LONG-SKIRTS-J', 'Long Skirts', 'Bottoms', 'Standard', null, null, 'Long Skirts', 'J', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LONG-SKIRTS-N', 'Long Skirts', 'Bottoms', 'Standard', null, null, 'Long Skirts', 'N', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LONG-SKIRTS-P', 'Long Skirts', 'Bottoms', 'Standard', null, null, 'Long Skirts', 'P', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LONG-SKIRTS-R', 'Long Skirts', 'Bottoms', 'Standard', null, null, 'Long Skirts', 'R', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LONG-SKIRTS-U', 'Long Skirts', 'Bottoms', 'Standard', null, null, 'Long Skirts', 'U', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-LONG-SKIRTS-Y', 'Long Skirts', 'Bottoms', 'Standard', null, null, 'Long Skirts', 'Y', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-SHORT-SKIRTS-D', 'Short Skirts', 'Bottoms', 'Standard', null, null, 'Short Skirts', 'D', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-SHORT-SKIRTS-F', 'Short Skirts', 'Bottoms', 'Standard', null, null, 'Short Skirts', 'F', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-SHORT-SKIRTS-H', 'Short Skirts', 'Bottoms', 'Standard', null, null, 'Short Skirts', 'H', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-SHORT-SKIRTS-J', 'Short Skirts', 'Bottoms', 'Standard', null, null, 'Short Skirts', 'J', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-SHORT-SKIRTS-N', 'Short Skirts', 'Bottoms', 'Standard', null, null, 'Short Skirts', 'N', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-SHORT-SKIRTS-P', 'Short Skirts', 'Bottoms', 'Standard', null, null, 'Short Skirts', 'P', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-SHORT-SKIRTS-R', 'Short Skirts', 'Bottoms', 'Standard', null, null, 'Short Skirts', 'R', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-SHORT-SKIRTS-U', 'Short Skirts', 'Bottoms', 'Standard', null, null, 'Short Skirts', 'U', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-SHORT-SKIRTS-Y', 'Short Skirts', 'Bottoms', 'Standard', null, null, 'Short Skirts', 'Y', 0, 0, 0, 0, 2, 'P&C Office', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-C', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'C', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-D', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'D', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-E', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'E', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-F', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'F', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-G', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'G', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-H', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'H', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-I', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'I', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-J', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'J', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-K', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'K', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-N', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'N', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-O', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'O', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-P', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'P', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-Q', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'Q', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-R', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'R', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-T', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'T', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-U', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'U', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-V', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'V', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-SHAPED-Y', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Shaped', null, 'Multi-pocket Pants', 'Y', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-C', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'C', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-D', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'D', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-E', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'E', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-F', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'F', 5, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-G', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'G', 5, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-H', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'H', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-I', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'I', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-J', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'J', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-K', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'K', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-N', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'N', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-O', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'O', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-P', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'P', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-Q', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'Q', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-R', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'R', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-T', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'T', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-U', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'U', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-V', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'V', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BOTTOMS-MULTI-POCKET-PANTS-STRAIGHT-Y', 'Multi-pocket Pants', 'Bottoms', 'Standard', 'Straight', null, 'Multi-pocket Pants', 'Y', 5, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-CD', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'CD', 15, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-EF', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'EF', 31, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-GH', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'GH', 30, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-IJ', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'IJ', 31, 0, 0, 4, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-KN', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'KN', 45, 0, 0, 2, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-OP', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'OP', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-QR', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'QR', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-TU', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-VY', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'VY', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-CD', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'CD', 0, 0, 0, 2, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-EF', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'EF', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-GH', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'GH', 0, 0, 0, 3, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-IJ', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'IJ', 12, 0, 0, 1, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-KN', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'KN', 7, 0, 0, 1, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-OP', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'OP', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-QR', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'QR', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-TU', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-VY', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'VY', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-CD', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'CD', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-EF', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'EF', 9, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-GH', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'GH', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-IJ', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'IJ', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-KN', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'KN', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-OP', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'OP', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-QR', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'QR', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-TU', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-SHAPED-VY', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'VY', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-CD', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'CD', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-EF', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'EF', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-GH', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'GH', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-IJ', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'IJ', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-KN', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'KN', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-OP', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'OP', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-QR', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'QR', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-TU', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-SHORT-SLEEVE-T-SHIRT-STRAIGHT-VY', 'Short-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Short Sleeve', 'Short-Sleeve T-Shirt', 'VY', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-CD', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'CD', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-EF', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'EF', 0, 0, 0, 2, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-GH', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'GH', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-IJ', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'IJ', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-KN', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'KN', 0, 0, 0, 6, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-OP', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'OP', 42, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-QR', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'QR', 8, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-TU', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-VY', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'VY', 12, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-CD', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'CD', 5, 0, 0, 1, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-EF', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'EF', 18, 0, 0, 1, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-GH', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'GH', 10, 0, 0, 3, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-IJ', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'IJ', 10, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-KN', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'KN', 17, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-OP', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'OP', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-QR', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'QR', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-TU', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-VY', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'VY', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-CD', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'CD', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-EF', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'EF', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-GH', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'GH', 14, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-IJ', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'IJ', 9, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-KN', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'KN', 31, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-OP', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'OP', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-QR', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'QR', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-TU', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-SHAPED-VY', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'VY', 30, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-CD', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'CD', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-EF', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'EF', 19, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-GH', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'GH', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-IJ', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'IJ', 13, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-KN', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'KN', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-OP', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'OP', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-QR', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'QR', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-TU', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('TOPS-LONG-SLEEVE-T-SHIRT-STRAIGHT-VY', 'Long-Sleeve T-Shirt', 'Tops', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve T-Shirt', 'VY', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-SHAPED-CD', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve Sweater', 'CD', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-SHAPED-EF', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve Sweater', 'EF', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-SHAPED-GH', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve Sweater', 'GH', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-SHAPED-IJ', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve Sweater', 'IJ', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-SHAPED-KN', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve Sweater', 'KN', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-SHAPED-OP', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve Sweater', 'OP', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-SHAPED-QR', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve Sweater', 'QR', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-SHAPED-TU', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve Sweater', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-SHAPED-VY', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Shaped', 'Long Sleeve', 'Long-Sleeve Sweater', 'VY', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-STRAIGHT-CD', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve Sweater', 'CD', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-STRAIGHT-EF', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve Sweater', 'EF', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-STRAIGHT-GH', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve Sweater', 'GH', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-STRAIGHT-IJ', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve Sweater', 'IJ', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-STRAIGHT-KN', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve Sweater', 'KN', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-STRAIGHT-OP', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve Sweater', 'OP', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-STRAIGHT-QR', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve Sweater', 'QR', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-STRAIGHT-TU', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve Sweater', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('SWEATERS-LONG-SLEEVE-SWEATER-STRAIGHT-VY', 'Long-Sleeve Sweater', 'Sweaters', 'Standard', 'Straight', 'Long Sleeve', 'Long-Sleeve Sweater', 'VY', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-CD', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'CD', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-EF', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'EF', 6, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-GH', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'GH', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-IJ', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'IJ', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-KN', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'KN', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-OP', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'OP', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-QR', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'QR', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-TU', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-VY', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'VY', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-CD', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'CD', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-EF', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'EF', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-GH', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'GH', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-IJ', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'IJ', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-KN', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'KN', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-OP', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'OP', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-QR', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'QR', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-TU', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-VY', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'VY', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-CD', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'CD', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-EF', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'EF', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-GH', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'GH', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-IJ', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'IJ', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-KN', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'KN', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-OP', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'OP', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-QR', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'QR', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-TU', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-VY', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'VY', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-CD', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'CD', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-EF', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'EF', 6, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-GH', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'GH', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-IJ', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'IJ', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-KN', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'KN', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-OP', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'OP', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-QR', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'QR', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-TU', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-VY', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'VY', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-SHAPED-CD', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Multi-pocket Jackets', 'CD', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-SHAPED-EF', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Multi-pocket Jackets', 'EF', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-SHAPED-GH', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Multi-pocket Jackets', 'GH', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-SHAPED-IJ', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Multi-pocket Jackets', 'IJ', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-SHAPED-KN', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Multi-pocket Jackets', 'KN', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-SHAPED-OP', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Multi-pocket Jackets', 'OP', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-SHAPED-QR', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Multi-pocket Jackets', 'QR', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-SHAPED-TU', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Multi-pocket Jackets', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-SHAPED-VY', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Multi-pocket Jackets', 'VY', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-STRAIGHT-CD', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Multi-pocket Jackets', 'CD', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-STRAIGHT-EF', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Multi-pocket Jackets', 'EF', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-STRAIGHT-GH', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Multi-pocket Jackets', 'GH', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-STRAIGHT-IJ', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Multi-pocket Jackets', 'IJ', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-STRAIGHT-KN', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Multi-pocket Jackets', 'KN', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-STRAIGHT-OP', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Multi-pocket Jackets', 'OP', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-STRAIGHT-QR', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Multi-pocket Jackets', 'QR', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-STRAIGHT-TU', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Multi-pocket Jackets', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-MULTI-POCKET-JACKETS-STRAIGHT-VY', 'Multi-pocket Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Multi-pocket Jackets', 'VY', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-SHAPED-C', 'Vests', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Vests', 'C', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-SHAPED-D', 'Vests', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Vests', 'D', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-SHAPED-F', 'Vests', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Vests', 'F', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-SHAPED-H', 'Vests', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Vests', 'H', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-SHAPED-J', 'Vests', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Vests', 'J', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-SHAPED-K', 'Vests', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Vests', 'K', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-SHAPED-N', 'Vests', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Vests', 'N', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-SHAPED-O', 'Vests', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Vests', 'O', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-SHAPED-P', 'Vests', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Vests', 'P', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-SHAPED-Q', 'Vests', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Vests', 'Q', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-SHAPED-R', 'Vests', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Vests', 'R', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-SHAPED-U', 'Vests', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Vests', 'U', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-SHAPED-V', 'Vests', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Vests', 'V', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-SHAPED-Y', 'Vests', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Vests', 'Y', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-STRAIGHT-D', 'Vests', 'Jackets & Vests', 'Standard', 'Straight', null, 'Vests', 'D', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-STRAIGHT-E', 'Vests', 'Jackets & Vests', 'Standard', 'Straight', null, 'Vests', 'E', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-STRAIGHT-F', 'Vests', 'Jackets & Vests', 'Standard', 'Straight', null, 'Vests', 'F', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-STRAIGHT-H', 'Vests', 'Jackets & Vests', 'Standard', 'Straight', null, 'Vests', 'H', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-STRAIGHT-I', 'Vests', 'Jackets & Vests', 'Standard', 'Straight', null, 'Vests', 'I', 3, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-STRAIGHT-J', 'Vests', 'Jackets & Vests', 'Standard', 'Straight', null, 'Vests', 'J', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-STRAIGHT-K', 'Vests', 'Jackets & Vests', 'Standard', 'Straight', null, 'Vests', 'K', 2, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-STRAIGHT-N', 'Vests', 'Jackets & Vests', 'Standard', 'Straight', null, 'Vests', 'N', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-STRAIGHT-P', 'Vests', 'Jackets & Vests', 'Standard', 'Straight', null, 'Vests', 'P', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-STRAIGHT-R', 'Vests', 'Jackets & Vests', 'Standard', 'Straight', null, 'Vests', 'R', 1, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-STRAIGHT-U', 'Vests', 'Jackets & Vests', 'Standard', 'Straight', null, 'Vests', 'U', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-STRAIGHT-V', 'Vests', 'Jackets & Vests', 'Standard', 'Straight', null, 'Vests', 'V', 4, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-VESTS-STRAIGHT-Y', 'Vests', 'Jackets & Vests', 'Standard', 'Straight', null, 'Vests', 'Y', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-SHAPED-D', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Kitchen Jackets', 'D', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-SHAPED-F', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Kitchen Jackets', 'F', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-SHAPED-H', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Kitchen Jackets', 'H', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-SHAPED-J', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Kitchen Jackets', 'J', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-SHAPED-N', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Kitchen Jackets', 'N', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-SHAPED-P', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Kitchen Jackets', 'P', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-SHAPED-R', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Kitchen Jackets', 'R', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-SHAPED-U', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Kitchen Jackets', 'U', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-SHAPED-Y', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Kitchen Jackets', 'Y', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-STRAIGHT-D', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Kitchen Jackets', 'D', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-STRAIGHT-F', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Kitchen Jackets', 'F', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-STRAIGHT-H', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Kitchen Jackets', 'H', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-STRAIGHT-J', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Kitchen Jackets', 'J', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-STRAIGHT-N', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Kitchen Jackets', 'N', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-STRAIGHT-P', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Kitchen Jackets', 'P', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-STRAIGHT-R', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Kitchen Jackets', 'R', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-STRAIGHT-U', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Kitchen Jackets', 'U', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-KITCHEN-JACKETS-STRAIGHT-Y', 'Kitchen Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Kitchen Jackets', 'Y', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-CD', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'CD', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-CD', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'CD', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-EF', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'EF', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-EF', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'EF', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-GH', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'GH', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-GH', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'GH', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-IJ', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'IJ', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-IJ', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'IJ', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-KN', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'KN', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-KN', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'KN', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-OP', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'OP', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-OP', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'OP', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-QR', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'QR', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-QR', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'QR', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-TU', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-TU', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'TU', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-VY', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'VY', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-SHAPED-VY', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Shaped', null, 'Full-Zip Jackets', 'VY', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-CD', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'CD', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-CD', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'CD', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-EF', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'EF', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-EF', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'EF', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-GH', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'GH', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-GH', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'GH', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-IJ', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'IJ', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-IJ', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'IJ', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-KN', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'KN', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-KN', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'KN', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-OP', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'OP', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-OP', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'OP', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-QR', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'QR', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-QR', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'QR', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-TU', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'TU', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-TU', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'TU', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-VY', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'VY', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('JACKETS-VESTS-FULL-ZIP-JACKETS-STRAIGHT-VY', 'Full-Zip Jackets', 'Jackets & Vests', 'Standard', 'Straight', null, 'Full-Zip Jackets', 'VY', 0, 0, 0, 0, 2, 'EMPU', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-C', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'C', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-D', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'D', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-E', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'E', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-F', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'F', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-G', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'G', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-H', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'H', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-I', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'I', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-J', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'J', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-K', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'K', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-N', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'N', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-O', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'O', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-P', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'P', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-Q', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'Q', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-R', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'R', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-T', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'T', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-U', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'U', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-V', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'V', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-Y', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'Y', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-C', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'C', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-D', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'D', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-E', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'E', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-F', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'F', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-G', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'G', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-H', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'H', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-I', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'I', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-J', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'J', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-K', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'K', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-N', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'N', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-O', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'O', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-P', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'P', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-Q', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'Q', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-R', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'R', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-T', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'T', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-U', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'U', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-V', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'V', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-SHAPED-Y', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Shaped', null, 'Button-Up Shirt', 'Y', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-C', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'C', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-D', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'D', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-E', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'E', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-F', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'F', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-G', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'G', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-H', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'H', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-I', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'I', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-J', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'J', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-K', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'K', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-N', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'N', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-O', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'O', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-P', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'P', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-Q', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'Q', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-R', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'R', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-T', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'T', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-U', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'U', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-V', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'V', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-Y', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'Y', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-C', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'C', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-D', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'D', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-E', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'E', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-F', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'F', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-G', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'G', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-H', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'H', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-I', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'I', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-J', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'J', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-K', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'K', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-N', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'N', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-O', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'O', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-P', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'P', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-Q', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'Q', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-R', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'R', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-T', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'T', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-U', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'U', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-V', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'V', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('BUTTON-UPS-BUTTON-UP-SHIRT-STRAIGHT-Y', 'Button-Up Shirt', 'Button Ups', 'Standard', 'Straight', null, 'Button-Up Shirt', 'Y', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-LANDYARD-ONE-SIZE', 'Landyard', 'Clothing Accessories', 'Standard', 'One Size', null, 'Landyard', 'ONE SIZE', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-NAME-TAG-ONE-SIZE', 'Name Tag', 'Clothing Accessories', 'Standard', 'One Size', null, 'Name Tag', 'ONE SIZE', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-BADGE-HOLDER-ONE-SIZE', 'Badge Holder', 'Clothing Accessories', 'Standard', 'One Size', null, 'Badge Holder', 'ONE SIZE', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-BEANIE-ONE-SIZE', 'Beanie', 'Clothing Accessories', 'Standard', 'One Size', null, 'Beanie', 'ONE SIZE', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-BELT-RING-ONE-SIZE', 'Belt Ring', 'Clothing Accessories', 'Standard', 'One Size', null, 'Belt Ring', 'ONE SIZE', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-BELT-ONE-SIZE', 'Belt', 'Clothing Accessories', 'Standard', 'One Size', null, 'Belt', 'ONE SIZE', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-SCARF-ONE-SIZE', 'Scarf', 'Clothing Accessories', 'Standard', 'One Size', null, 'Scarf', 'ONE SIZE', 0, 0, 0, 0, 2, 'N/A', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-TOOL-POUCH-ONE-SIZE', 'Tool Pouch', 'Clothing Accessories', 'Standard', 'One Size', null, 'Tool Pouch', 'ONE SIZE', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-BIB-APRON-C-J-ONE-SIZE', 'Bib Apron C/J', 'Clothing Accessories', 'Standard', 'One Size', null, 'Bib Apron C/J', 'ONE SIZE', 0, 0, 0, 0, 2, 'N/A', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-BIB-APRON-K-Y-ONE-SIZE', 'Bib Apron K/Y', 'Clothing Accessories', 'Standard', 'One Size', null, 'Bib Apron K/Y', 'ONE SIZE', 0, 0, 0, 0, 2, 'N/A', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-WAIST-APRON-CJ-ONE-SIZE', 'Waist Apron CJ', 'Clothing Accessories', 'Standard', 'One Size', null, 'Waist Apron CJ', 'ONE SIZE', 0, 0, 0, 0, 2, 'N/A', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-WAIST-APRON-KY-ONE-SIZE', 'Waist Apron KY', 'Clothing Accessories', 'Standard', 'One Size', null, 'Waist Apron KY', 'ONE SIZE', 0, 0, 0, 0, 2, 'N/A', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-BANDANA-55-58CM-ONE-SIZE', 'Bandana 55-58CM', 'Clothing Accessories', 'Standard', 'One Size', null, 'Bandana 55-58CM', 'ONE SIZE', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-BANDANA-58-61CM-ONE-SIZE', 'Bandana 58-61CM', 'Clothing Accessories', 'Standard', 'One Size', null, 'Bandana 58-61CM', 'ONE SIZE', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-PILLAR-HAT-55CM-ONE-SIZE', 'Pillar Hat 55CM', 'Clothing Accessories', 'Standard', 'One Size', null, 'Pillar Hat 55CM', 'ONE SIZE', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-PILLAR-HAT-58CM-ONE-SIZE', 'Pillar Hat 58CM', 'Clothing Accessories', 'Standard', 'One Size', null, 'Pillar Hat 58CM', 'ONE SIZE', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx'),
  ('CLOTHING-ACCESSORIES-PILLAR-HAT-61CM-ONE-SIZE', 'Pillar Hat 61CM', 'Clothing Accessories', 'Standard', 'One Size', null, 'Pillar Hat 61CM', 'ONE SIZE', 0, 0, 0, 0, 2, 'Uniform Room', 'Imported from Uniform Inventory Count.xlsx');

insert into public.inventory_stock_movements (
  inventory_item_id, qty_delta, movement_type, reason
)
select id, stock_quantity, 'seed', 'Initial seed quantity from Uniform Inventory Count.xlsx'
from public.inventory_items
where stock_quantity > 0;

commit;
