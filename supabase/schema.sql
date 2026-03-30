
-- Uniform Portal - FULL CORRECTED Supabase SQL
-- Safe for a fresh Supabase project with the default auth schema.
-- Includes:
--   tables
--   indexes
--   triggers
--   helper functions / RPCs
--   views
--   RLS policies
--   seed data
--
-- Fixes included:
--   1) no unsafe TRUNCATE on missing tables
--   2) no seed logic depending on request_number = 1/2/3
--   3) no infinite recursion in profiles RLS
--   4) safe rerun with DROP IF EXISTS / CASCADE

create extension if not exists pgcrypto;

-- =========================================================
-- CLEANUP
-- =========================================================

drop trigger if exists on_auth_user_created on auth.users;

drop function if exists public.handle_new_user() cascade;
drop function if exists public.set_updated_at() cascade;
drop function if exists public.size_rank(text) cascade;
drop function if exists public.lookup_employee_by_id(text) cascade;
drop function if exists public.get_inventory_availability(uuid) cascade;
drop function if exists public.reserve_inventory(uuid, integer) cascade;
drop function if exists public.release_inventory(uuid, integer) cascade;
drop function if exists public.apply_inventory_movement(uuid, integer, text, text, uuid, uuid) cascade;
drop function if exists public.submit_uniform_request(text, uuid, text, integer) cascade;
drop function if exists public.submit_uniform_request(text, text, text, text, text, text) cascade;
drop function if exists public.set_request_status(uuid, text, text, uuid) cascade;
drop function if exists public.create_admin_profile(uuid, text, text) cascade;
drop function if exists public.promote_profile_to_admin(uuid) cascade;
drop function if exists public.import_employees_from_json(jsonb) cascade;

drop view if exists public.v_inventory_available cascade;
drop view if exists public.v_request_analytics cascade;

drop table if exists public.request_history cascade;
drop table if exists public.request_items cascade;
drop table if exists public.uniform_requests cascade;
drop table if exists public.inventory_stock_movements cascade;
drop table if exists public.inventory_items cascade;
drop table if exists public.uniform_size_chart cascade;
drop table if exists public.employee_import_runs cascade;
drop table if exists public.employees cascade;
drop table if exists public.profiles cascade;

-- =========================================================
-- TABLES
-- =========================================================

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null unique,
  role text not null default 'employee' check (role in ('employee', 'admin')),
  department text,
  location text default 'Toronto',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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
  imported_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.uniform_size_chart (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('tops', 'bottoms', 'outerwear', 'general')),
  size_label text not null,
  chest_range text,
  waist_range text,
  hip_range text,
  inseam_range text,
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
  colour text not null,
  fit text,
  sleeve text,
  style text not null,
  size text not null,
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  reserved_quantity integer not null default 0 check (reserved_quantity >= 0),
  reorder_level integer not null default 2 check (reorder_level >= 0),
  unit text not null default 'pcs',
  is_active boolean not null default true,
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
    movement_type in (
      'seed',
      'restock',
      'adjustment',
      'reservation_release',
      'fulfillment',
      'manual_correction'
    )
  ),
  reason text,
  related_request_id uuid,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.uniform_requests (
  id uuid primary key default gen_random_uuid(),
  request_number bigint generated always as identity unique,
  created_by uuid references public.profiles(id) on delete set null,
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
  changed_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

-- =========================================================
-- INDEXES
-- =========================================================

create index idx_profiles_role on public.profiles(role);
create index idx_employees_active on public.employees(is_active);
create index idx_employees_department on public.employees(department);
create index idx_inventory_lookup on public.inventory_items(product_type, layer, colour, fit, sleeve, style, size);
create index idx_inventory_low_stock on public.inventory_items(is_active, reorder_level, stock_quantity, reserved_quantity);
create index idx_uniform_requests_status on public.uniform_requests(status, created_at desc);
create index idx_uniform_requests_employee on public.uniform_requests(employee_id, created_at desc);
create index idx_request_items_request_id on public.request_items(request_id);
create index idx_request_history_request_id on public.request_history(request_id, created_at desc);

-- =========================================================
-- HELPERS / TRIGGERS
-- =========================================================

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
language plpgsql
immutable
as $$
begin
  return case upper(coalesce(trim(p_size), ''))
    when 'XXS' then 1
    when 'XS' then 2
    when 'S' then 3
    when 'M' then 4
    when 'L' then 5
    when 'XL' then 6
    when '2XL' then 7
    when 'XXL' then 7
    when '3XL' then 8
    when 'XXXL' then 8
    when '4XL' then 9
    else 999
  end;
end;
$$;

create trigger trg_profiles_updated_at
before update on public.profiles
for each row execute procedure public.set_updated_at();

create trigger trg_employees_updated_at
before update on public.employees
for each row execute procedure public.set_updated_at();

create trigger trg_inventory_items_updated_at
before update on public.inventory_items
for each row execute procedure public.set_updated_at();

create trigger trg_uniform_requests_updated_at
before update on public.uniform_requests
for each row execute procedure public.set_updated_at();

-- =========================================================
-- AUTH / ADMIN
-- =========================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)),
    new.email,
    'employee'
  )
  on conflict (id) do update
    set full_name = excluded.full_name,
        email = excluded.email;

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.create_admin_profile(
  p_user_id uuid,
  p_full_name text,
  p_email text
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
begin
  insert into public.profiles (id, full_name, email, role)
  values (p_user_id, p_full_name, lower(p_email), 'admin')
  on conflict (id) do update
    set full_name = excluded.full_name,
        email = excluded.email,
        role = 'admin'
  returning * into v_profile;

  return v_profile;
end;
$$;

create or replace function public.promote_profile_to_admin(p_profile_id uuid)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
begin
  update public.profiles
     set role = 'admin'
   where id = p_profile_id
   returning * into v_profile;

  if not found then
    raise exception 'Profile not found';
  end if;

  return v_profile;
end;
$$;

-- =========================================================
-- RPCS
-- =========================================================

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

  if not found then
    raise exception 'Employee ID not found';
  end if;

  return v_employee;
end;
$$;

create or replace function public.get_inventory_availability(p_inventory_item_id uuid)
returns integer
language sql
stable
as $$
  select greatest(stock_quantity - reserved_quantity, 0)
  from public.inventory_items
  where id = p_inventory_item_id
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
    raise exception 'Reserve quantity must be greater than zero';
  end if;

  update public.inventory_items
     set reserved_quantity = reserved_quantity + p_qty
   where id = p_inventory_item_id
     and (stock_quantity - reserved_quantity) >= p_qty
  returning * into v_item;

  if not found then
    raise exception 'Insufficient available stock';
  end if;

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
    raise exception 'Release quantity must be greater than zero';
  end if;

  update public.inventory_items
     set reserved_quantity = greatest(reserved_quantity - p_qty, 0)
   where id = p_inventory_item_id
  returning * into v_item;

  if not found then
    raise exception 'Inventory item not found';
  end if;

  return v_item;
end;
$$;

create or replace function public.apply_inventory_movement(
  p_inventory_item_id uuid,
  p_qty_delta integer,
  p_movement_type text,
  p_reason text default null,
  p_related_request_id uuid default null,
  p_created_by uuid default null
)
returns public.inventory_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.inventory_items%rowtype;
begin
  if p_qty_delta = 0 then
    raise exception 'Quantity delta cannot be zero';
  end if;

  update public.inventory_items
     set stock_quantity = stock_quantity + p_qty_delta
   where id = p_inventory_item_id
     and stock_quantity + p_qty_delta >= 0
  returning * into v_item;

  if not found then
    raise exception 'Stock movement would make quantity negative or item was not found';
  end if;

  insert into public.inventory_stock_movements (
    inventory_item_id,
    qty_delta,
    movement_type,
    reason,
    related_request_id,
    created_by
  ) values (
    p_inventory_item_id,
    p_qty_delta,
    p_movement_type,
    p_reason,
    p_related_request_id,
    p_created_by
  );

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
      and coalesce(layer, '') = coalesce(v_item.layer, '')
      and colour = v_item.colour
      and coalesce(fit, '') = coalesce(v_item.fit, '')
      and coalesce(sleeve, '') = coalesce(v_item.sleeve, '')
      and style = v_item.style
      and public.size_rank(size) > public.size_rank(v_item.size)
      and (stock_quantity - reserved_quantity) >= p_quantity
    order by public.size_rank(size)
    limit 1
    for update;

    if found then
      perform public.reserve_inventory(v_size_up.id, p_quantity);
      v_mode := 'size_up';
    else
      v_mode := 'special_request';
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
    case when v_mode = 'in_stock' then v_item.id
         when v_mode = 'size_up' then v_size_up.id
         else null end,
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

  insert into public.request_history (request_id, action, old_status, new_status, message)
  values (
    v_request.id,
    'created',
    null,
    'pending',
    case
      when v_mode = 'in_stock' then 'Request created. Requested size reserved from stock.'
      when v_mode = 'size_up' then 'Requested size unavailable. Next available size up reserved.'
      else 'No stock available. Request marked as special request.'
    end
  );

  return v_request;
end;
$$;

create or replace function public.submit_uniform_request(
  p_employee_id text,
  p_product_type text,
  p_style text,
  p_colour text,
  p_requested_size text,
  p_notes text default null
)
returns public.uniform_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inventory_id uuid;
begin
  select id into v_inventory_id
  from public.inventory_items
  where is_active = true
    and product_type = p_product_type
    and style = p_style
    and colour = p_colour
    and size = p_requested_size
  order by created_at
  limit 1;

  if v_inventory_id is null then
    raise exception 'Inventory item not found for the selected product';
  end if;

  return public.submit_uniform_request(p_employee_id, v_inventory_id, p_notes, 1);
end;
$$;

create or replace function public.set_request_status(
  p_request_id uuid,
  p_new_status text,
  p_message text default null,
  p_changed_by uuid default null
)
returns public.uniform_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.uniform_requests%rowtype;
  v_item record;
  v_result public.uniform_requests%rowtype;
begin
  select * into v_request
  from public.uniform_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Request not found';
  end if;

  if p_new_status not in ('pending', 'approved', 'ordered', 'fulfilled', 'rejected', 'cancelled') then
    raise exception 'Invalid status';
  end if;

  for v_item in
    select * from public.request_items where request_id = p_request_id
  loop
    if p_new_status in ('rejected', 'cancelled')
       and v_request.status not in ('rejected', 'cancelled', 'fulfilled')
       and v_item.reserved_item_id is not null then
      perform public.release_inventory(v_item.reserved_item_id, v_item.quantity);
      update public.request_items
         set line_status = p_new_status
       where id = v_item.id;

    elsif p_new_status = 'fulfilled'
       and v_request.status <> 'fulfilled'
       and v_item.reserved_item_id is not null then
      perform public.release_inventory(v_item.reserved_item_id, v_item.quantity);
      perform public.apply_inventory_movement(
        v_item.reserved_item_id,
        -1 * v_item.quantity,
        'fulfillment',
        coalesce(p_message, 'Item fulfilled'),
        p_request_id,
        p_changed_by
      );
      update public.request_items
         set line_status = 'fulfilled'
       where id = v_item.id;

    elsif p_new_status in ('approved', 'ordered') then
      update public.request_items
         set line_status = p_new_status
       where id = v_item.id;
    end if;
  end loop;

  update public.uniform_requests
     set status = p_new_status,
         admin_notes = coalesce(p_message, admin_notes)
   where id = p_request_id
   returning * into v_result;

  insert into public.request_history (request_id, action, old_status, new_status, message, changed_by)
  values (p_request_id, 'status_changed', v_request.status, p_new_status, p_message, p_changed_by);

  return v_result;
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
  if jsonb_typeof(p_payload) <> 'array' then
    raise exception 'Payload must be a JSON array';
  end if;

  insert into public.employee_import_runs (payload, imported_count)
  values (p_payload, jsonb_array_length(p_payload));

  for v_item in select * from jsonb_array_elements(p_payload)
  loop
    insert into public.employees (
      employee_id,
      full_name,
      ikea_email,
      department,
      job_title,
      location,
      size_top,
      size_bottom,
      is_active,
      imported_at
    ) values (
      trim(v_item ->> 'employee_id'),
      trim(v_item ->> 'full_name'),
      lower(trim(v_item ->> 'ikea_email')),
      nullif(trim(v_item ->> 'department'), ''),
      nullif(trim(v_item ->> 'job_title'), ''),
      coalesce(nullif(trim(v_item ->> 'location'), ''), 'Toronto'),
      nullif(trim(v_item ->> 'size_top'), ''),
      nullif(trim(v_item ->> 'size_bottom'), ''),
      coalesce((v_item ->> 'is_active')::boolean, true),
      now()
    )
    on conflict (employee_id) do update
      set full_name   = excluded.full_name,
          ikea_email  = excluded.ikea_email,
          department  = excluded.department,
          job_title   = excluded.job_title,
          location    = excluded.location,
          size_top    = excluded.size_top,
          size_bottom = excluded.size_bottom,
          is_active   = excluded.is_active,
          imported_at = now(),
          updated_at  = now();

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

grant execute on function public.lookup_employee_by_id(text) to anon, authenticated;
grant execute on function public.get_inventory_availability(uuid) to anon, authenticated;
grant execute on function public.submit_uniform_request(text, uuid, text, integer) to anon, authenticated;
grant execute on function public.submit_uniform_request(text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.set_request_status(uuid, text, text, uuid) to authenticated;
grant execute on function public.promote_profile_to_admin(uuid) to authenticated;
grant execute on function public.import_employees_from_json(jsonb) to authenticated;

-- =========================================================
-- VIEWS
-- =========================================================

create or replace view public.v_inventory_available as
select
  i.*,
  greatest(i.stock_quantity - i.reserved_quantity, 0) as available_quantity,
  case
    when greatest(i.stock_quantity - i.reserved_quantity, 0) <= i.reorder_level then true
    else false
  end as is_low_stock
from public.inventory_items i;

create or replace view public.v_request_analytics as
select
  ri.product_type,
  ri.style,
  ri.colour,
  ri.requested_size,
  ri.requested_size as size,
  concat_ws(' · ', ri.product_type, ri.style, ri.colour) as item_label,
  count(*) as total_lines,
  sum(ri.quantity) as total_qty,
  count(*) filter (where ur.status in ('approved', 'ordered', 'fulfilled')) as progressed_count,
  count(*) filter (where ur.fulfillment_mode = 'in_stock') as in_stock_count,
  count(*) filter (where ur.fulfillment_mode = 'size_up') as size_up_count,
  count(*) filter (where ur.fulfillment_mode = 'special_request') as special_request_count
from public.request_items ri
join public.uniform_requests ur on ur.id = ri.request_id
group by ri.product_type, ri.style, ri.colour, ri.requested_size

-- =========================================================
-- RLS
-- =========================================================

alter table public.profiles enable row level security;
alter table public.employees enable row level security;
alter table public.employee_import_runs enable row level security;
alter table public.uniform_size_chart enable row level security;
alter table public.inventory_items enable row level security;
alter table public.inventory_stock_movements enable row level security;
alter table public.uniform_requests enable row level security;
alter table public.request_items enable row level security;
alter table public.request_history enable row level security;

-- IMPORTANT:
-- No admin self-check against public.profiles inside profiles policies,
-- because that creates infinite recursion.
create policy "profiles_select_own"
on public.profiles
for select
to authenticated
using (
  id = auth.uid()
);

create policy "profiles_update_own"
on public.profiles
for update
to authenticated
using (
  id = auth.uid()
)
with check (
  id = auth.uid()
);

create policy "employees_read_all"
on public.employees
for select
to anon, authenticated
using (true);

create policy "employees_admin_write"
on public.employees
for all
to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
)
with check (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  )
);

create policy "size_chart_read_all"
on public.uniform_size_chart
for select
to anon, authenticated
using (true);

create policy "size_chart_admin_write"
on public.uniform_size_chart
for all
to authenticated
using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
)
with check (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
);

create policy "inventory_read_all"
on public.inventory_items
for select
to anon, authenticated
using (true);

create policy "inventory_admin_write"
on public.inventory_items
for all
to authenticated
using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
)
with check (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
);

create policy "stock_movements_admin_read_write"
on public.inventory_stock_movements
for all
to authenticated
using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
)
with check (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
);

create policy "requests_insert_public"
on public.uniform_requests
for insert
to anon, authenticated
with check (true);

create policy "requests_read_own_or_admin"
on public.uniform_requests
for select
to authenticated
using (
  created_by = auth.uid()
  or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
);

create policy "requests_admin_update"
on public.uniform_requests
for update
to authenticated
using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
)
with check (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
);

create policy "request_items_insert_public"
on public.request_items
for insert
to anon, authenticated
with check (true);

create policy "request_items_read_own_or_admin"
on public.request_items
for select
to authenticated
using (
  exists (
    select 1
    from public.uniform_requests ur
    where ur.id = request_id
      and (
        ur.created_by = auth.uid()
        or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
      )
  )
);

create policy "request_items_admin_update"
on public.request_items
for update
to authenticated
using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
)
with check (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
);

create policy "request_history_admin_read"
on public.request_history
for select
to authenticated
using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
);

create policy "request_history_insert_public"
on public.request_history
for insert
to anon, authenticated
with check (true);

create policy "employee_import_runs_admin_only"
on public.employee_import_runs
for all
to authenticated
using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
)
with check (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
);

-- =========================================================
-- SEED
-- =========================================================

insert into public.uniform_size_chart (category, size_label, chest_range, waist_range, hip_range, inseam_range, fit_note, sort_order)
values
  ('general', 'XS',  '32-34 in', '26-28 in', '34-36 in', null, 'Slim fit reference', 1),
  ('general', 'S',   '35-37 in', '29-31 in', '37-39 in', null, 'Standard small', 2),
  ('general', 'M',   '38-40 in', '32-34 in', '40-42 in', null, 'Standard medium', 3),
  ('general', 'L',   '41-43 in', '35-37 in', '43-45 in', null, 'Standard large', 4),
  ('general', 'XL',  '44-46 in', '38-40 in', '46-48 in', null, 'Standard extra large', 5),
  ('general', '2XL', '47-50 in', '41-44 in', '49-52 in', null, 'Plus size reference', 6),
  ('general', '3XL', '51-54 in', '45-48 in', '53-56 in', null, 'Extended plus size reference', 7),
  ('bottoms', '28', null, '28 in', '36-37 in', '30-32 in', 'Straight or shaped by cut', 1),
  ('bottoms', '30', null, '30 in', '38-39 in', '30-32 in', 'Straight or shaped by cut', 2),
  ('bottoms', '32', null, '32 in', '40-41 in', '30-32 in', 'Straight or shaped by cut', 3),
  ('bottoms', '34', null, '34 in', '42-43 in', '30-32 in', 'Straight or shaped by cut', 4),
  ('bottoms', '36', null, '36 in', '44-45 in', '30-32 in', 'Straight or shaped by cut', 5),
  ('bottoms', '38', null, '38 in', '46-47 in', '30-32 in', 'Straight or shaped by cut', 6);

insert into public.employees (
  employee_id,
  full_name,
  ikea_email,
  department,
  job_title,
  location,
  size_top,
  size_bottom,
  imported_at
) values
  ('100001', 'Amanda Silva', 'amanda.silva@ikea.com', 'Fulfillment Operations', 'Co-worker', 'Toronto', 'M', '32', now()),
  ('100002', 'Denis Costa', 'denis.costa@ikea.com', 'Fulfillment Operations', 'Co-worker', 'Toronto', 'L', '34', now()),
  ('100003', 'Andrew Plumer', 'andrew.plumer@ikea.com', 'IKEA Food', 'Co-worker', 'Toronto', 'L', '34', now()),
  ('100004', 'Dayana Rocha', 'dayana.rocha@ikea.com', 'Customer Service', 'Co-worker', 'Toronto', 'S', '30', now()),
  ('100005', 'Luca Test', 'luca.test@ikea.com', 'Sales Living Room', 'Co-worker', 'Toronto', 'XS', '28', now());

insert into public.inventory_items (
  sku, product_type, layer, colour, fit, sleeve, style, size,
  stock_quantity, reserved_quantity, reorder_level, notes
) values
  ('TOP-SHIRT-YLW-STR-SS-XS', 'Top', 'Shirt', 'Yellow', 'Straight', 'Short Sleeve', 'Standard', 'XS', 8, 0, 2, 'Seed from workbook model'),
  ('TOP-SHIRT-YLW-STR-SS-S',  'Top', 'Shirt', 'Yellow', 'Straight', 'Short Sleeve', 'Standard', 'S', 12, 0, 2, 'Seed from workbook model'),
  ('TOP-SHIRT-YLW-STR-SS-M',  'Top', 'Shirt', 'Yellow', 'Straight', 'Short Sleeve', 'Standard', 'M', 15, 0, 3, 'Seed from workbook model'),
  ('TOP-SHIRT-YLW-STR-SS-L',  'Top', 'Shirt', 'Yellow', 'Straight', 'Short Sleeve', 'Standard', 'L', 9, 0, 2, 'Seed from workbook model'),
  ('TOP-SHIRT-BLU-SHP-SS-S',  'Top', 'Shirt', 'Blue',   'Shaped',   'Short Sleeve', 'Standard', 'S', 7, 0, 2, 'Seed from workbook model'),
  ('TOP-SHIRT-BLU-SHP-SS-M',  'Top', 'Shirt', 'Blue',   'Shaped',   'Short Sleeve', 'Standard', 'M', 11, 0, 2, 'Seed from workbook model'),
  ('OUT-ZIPHD-BLU-NA-NA-M',   'Outer Layer', 'Layer 2 - Zip Hoodie', 'Blue', 'NA', 'NA', 'Zip Hoodie', 'M', 6, 0, 1, 'Seed from workbook model'),
  ('OUT-ZIPHD-BLU-NA-NA-L',   'Outer Layer', 'Layer 2 - Zip Hoodie', 'Blue', 'NA', 'NA', 'Zip Hoodie', 'L', 3, 0, 1, 'Seed from workbook model'),
  ('BOT-PANT-BLU-STR-NA-30-4P', 'Bottoms', 'Pants', 'Blue', 'Straight', 'NA', '4 Pockets', '30', 12, 0, 2, 'Seed from workbook model'),
  ('BOT-PANT-BLU-STR-NA-32-4P', 'Bottoms', 'Pants', 'Blue', 'Straight', 'NA', '4 Pockets', '32', 10, 0, 2, 'Seed from workbook model'),
  ('BOT-PANT-BLU-STR-NA-34-2P', 'Bottoms', 'Pants', 'Blue', 'Straight', 'NA', '2 Pockets', '34', 7, 0, 2, 'Seed from workbook model');

insert into public.inventory_stock_movements (
  inventory_item_id,
  qty_delta,
  movement_type,
  reason
)
select id, stock_quantity, 'seed', 'Initial seed quantity'
from public.inventory_items;

do $$
declare
  v_req1 uuid;
  v_req2 uuid;
  v_req3 uuid;
begin
  select (public.submit_uniform_request('100001', 'Top', 'Standard', 'Yellow', 'M', 'Need replacement shirt')).id into v_req1;
  select (public.submit_uniform_request('100002', 'Bottoms', '4 Pockets', 'Blue', '32', 'New starter issue')).id into v_req2;
  select (public.submit_uniform_request('100004', 'Outer Layer', 'Zip Hoodie', 'Blue', 'M', 'Cold weather')).id into v_req3;

  update public.uniform_requests
     set created_at = now() - interval '8 days'
   where id = v_req1;

  update public.uniform_requests
     set created_at = now() - interval '5 days'
   where id = v_req2;

  update public.uniform_requests
     set created_at = now() - interval '2 days'
   where id = v_req3;

  perform public.set_request_status(v_req1, 'fulfilled', 'Handed to co-worker at collection point', null);
  perform public.set_request_status(v_req2, 'approved', 'Approved by admin', null);
  perform public.set_request_status(v_req3, 'ordered', 'Not enough preferred size in stock, external order requested', null);
end $$;

-- =========================================================
-- NOTES
-- =========================================================
-- 1) Admin creation in Supabase Auth should still happen in your backend
--    using SUPABASE_SERVICE_ROLE_KEY.
-- 2) After creating the auth user, call:
--      public.create_admin_profile(user_id, full_name, email)
--    or:
--      public.promote_profile_to_admin(profile_id)
-- 3) Public request page can use:
--      public.lookup_employee_by_id(employee_id)
--      public.submit_uniform_request(...)
