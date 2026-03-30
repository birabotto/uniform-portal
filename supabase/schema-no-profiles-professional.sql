-- Uniform Portal - professional schema without profiles
-- Any authenticated Supabase Auth user can access /admin
-- Public QR flow remains available through SECURITY DEFINER RPCs

begin;

create extension if not exists pgcrypto;

-- =========================================================
-- CLEANUP
-- =========================================================

drop view if exists public.v_request_analytics cascade;
drop view if exists public.v_inventory_available cascade;

drop trigger if exists trg_employees_updated_at on public.employees;
drop trigger if exists trg_inventory_items_updated_at on public.inventory_items;
drop trigger if exists trg_uniform_requests_updated_at on public.uniform_requests;

drop function if exists public.set_updated_at() cascade;
drop function if exists public.size_rank(text) cascade;
drop function if exists public.lookup_employee_by_id(text) cascade;
drop function if exists public.add_stock(uuid, integer) cascade;
drop function if exists public.submit_uniform_request(text, text, text, text, text, text) cascade;
drop function if exists public.set_request_status(uuid, text, text, uuid) cascade;
drop function if exists public.import_employees_from_json(jsonb) cascade;

drop table if exists public.request_history cascade;
drop table if exists public.request_items cascade;
drop table if exists public.uniform_requests cascade;
drop table if exists public.inventory_stock_movements cascade;
drop table if exists public.inventory_items cascade;
drop table if exists public.uniform_size_chart cascade;
drop table if exists public.employee_import_runs cascade;
drop table if exists public.employees cascade;

-- =========================================================
-- TABLES
-- =========================================================

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

-- =========================================================
-- INDEXES
-- =========================================================

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
    return null;
  end if;

  return v_employee;
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

  insert into public.inventory_stock_movements (
    inventory_item_id,
    qty_delta,
    movement_type,
    reason,
    created_by
  ) values (
    p_item_id,
    p_amount,
    'restock',
    'Stock added from dashboard',
    auth.uid()
  );

  return v_item;
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
  v_employee public.employees%rowtype;
  v_exact_item public.inventory_items%rowtype;
  v_size_up_item public.inventory_items%rowtype;
  v_request public.uniform_requests%rowtype;
  v_fulfillment_mode text := 'special_request';
  v_suggested_size text := null;
  v_line_status text := 'pending';
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

  select *
    into v_exact_item
    from public.inventory_items
   where is_active = true
     and product_type = p_product_type
     and style = p_style
     and colour = p_colour
     and size = p_requested_size
   limit 1;

  if found and (v_exact_item.stock_quantity - v_exact_item.reserved_quantity) >= 1 then
    v_fulfillment_mode := 'in_stock';
    v_line_status := 'reserved';

    update public.inventory_items
       set reserved_quantity = reserved_quantity + 1
     where id = v_exact_item.id;

    insert into public.inventory_stock_movements (
      inventory_item_id,
      qty_delta,
      movement_type,
      reason,
      created_by
    ) values (
      v_exact_item.id,
      1,
      'reservation',
      'Reserved automatically on request submit',
      auth.uid()
    );
  else
    select *
      into v_size_up_item
      from public.inventory_items
     where is_active = true
       and product_type = p_product_type
       and style = p_style
       and colour = p_colour
       and public.size_rank(size) > public.size_rank(p_requested_size)
       and (stock_quantity - reserved_quantity) >= 1
     order by public.size_rank(size)
     limit 1;

    if found then
      v_fulfillment_mode := 'size_up';
      v_suggested_size := v_size_up_item.size;
    end if;
  end if;

  insert into public.uniform_requests (
    created_by,
    employee_record_id,
    employee_id,
    employee_name,
    employee_email,
    employee_department,
    fulfillment_mode,
    status,
    notes
  ) values (
    auth.uid(),
    v_employee.id,
    v_employee.employee_id,
    v_employee.full_name,
    v_employee.ikea_email,
    v_employee.department,
    v_fulfillment_mode,
    'pending',
    p_notes
  ) returning * into v_request;

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
    coalesce(v_exact_item.id, v_size_up_item.id),
    case when v_fulfillment_mode = 'in_stock' then v_exact_item.id else null end,
    p_product_type,
    coalesce(v_exact_item.layer, v_size_up_item.layer),
    p_colour,
    coalesce(v_exact_item.fit, v_size_up_item.fit),
    coalesce(v_exact_item.sleeve, v_size_up_item.sleeve),
    p_style,
    p_requested_size,
    v_suggested_size,
    1,
    v_line_status
  );

  insert into public.request_history (
    request_id,
    action,
    old_status,
    new_status,
    message,
    changed_by
  ) values (
    v_request.id,
    'created',
    null,
    'pending',
    'Request created from public form',
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

  if v_old_status = p_new_status and coalesce(p_message, '') = '' then
    return v_request;
  end if;

  if p_new_status in ('rejected', 'cancelled') and v_old_status not in ('rejected', 'cancelled', 'fulfilled') then
    for v_line in
      select * from public.request_items where request_id = p_request_id and reserved_item_id is not null
    loop
      update public.inventory_items
         set reserved_quantity = greatest(reserved_quantity - v_line.quantity, 0)
       where id = v_line.reserved_item_id;

      insert into public.inventory_stock_movements (
        inventory_item_id,
        qty_delta,
        movement_type,
        reason,
        related_request_id,
        created_by
      ) values (
        v_line.reserved_item_id,
        -v_line.quantity,
        'reservation_release',
        coalesce(p_message, 'Reservation released after request status change'),
        p_request_id,
        p_changed_by
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
        inventory_item_id,
        qty_delta,
        movement_type,
        reason,
        related_request_id,
        created_by
      ) values (
        v_line.reserved_item_id,
        -v_line.quantity,
        'fulfillment',
        coalesce(p_message, 'Stock fulfilled for request'),
        p_request_id,
        p_changed_by
      );
    end loop;
  end if;

  update public.request_items
     set line_status = case
       when p_new_status = 'approved' then case when reserved_item_id is not null then 'approved' else 'approved' end
       when p_new_status = 'ordered' then 'ordered'
       when p_new_status = 'fulfilled' then 'fulfilled'
       when p_new_status = 'rejected' then 'rejected'
       when p_new_status = 'cancelled' then 'cancelled'
       else line_status
     end
   where request_id = p_request_id;

  update public.uniform_requests
     set status = p_new_status,
         admin_notes = coalesce(p_message, admin_notes)
   where id = p_request_id
   returning * into v_request;

  insert into public.request_history (
    request_id,
    action,
    old_status,
    new_status,
    message,
    changed_by
  ) values (
    p_request_id,
    'status_changed',
    v_old_status,
    p_new_status,
    p_message,
    p_changed_by
  );

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
      employee_id,
      full_name,
      ikea_email,
      department,
      location,
      is_active,
      imported_at
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
  ur.id,
  ur.request_number,
  ur.employee_id,
  ur.employee_name,
  ur.employee_email,
  ur.employee_department,
  ur.fulfillment_mode,
  ur.status,
  ur.created_at,
  count(ri.id) as line_count,
  coalesce(sum(ri.quantity), 0) as total_units
from public.uniform_requests ur
left join public.request_items ri on ri.request_id = ur.id
group by ur.id;

-- =========================================================
-- GRANTS
-- =========================================================

grant usage on schema public to anon, authenticated;

grant select on public.inventory_items to anon;
grant select on public.uniform_size_chart to anon;
grant select on public.v_inventory_available to anon;

grant select on public.employees to authenticated;
grant select, insert, update, delete on public.employee_import_runs to authenticated;
grant select, insert, update, delete on public.uniform_size_chart to authenticated;
grant select, insert, update, delete on public.inventory_items to authenticated;
grant select, insert, update, delete on public.inventory_stock_movements to authenticated;
grant select, insert, update, delete on public.uniform_requests to authenticated;
grant select, insert, update, delete on public.request_items to authenticated;
grant select, insert, update, delete on public.request_history to authenticated;
grant select, insert, update, delete on public.employees to authenticated;
grant select on public.v_inventory_available to authenticated;
grant select on public.v_request_analytics to authenticated;

grant execute on function public.lookup_employee_by_id(text) to anon, authenticated;
grant execute on function public.add_stock(uuid, integer) to authenticated;
grant execute on function public.submit_uniform_request(text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.set_request_status(uuid, text, text, uuid) to authenticated;
grant execute on function public.import_employees_from_json(jsonb) to authenticated;

-- =========================================================
-- RLS
-- =========================================================

alter table public.employees enable row level security;
alter table public.employee_import_runs enable row level security;
alter table public.uniform_size_chart enable row level security;
alter table public.inventory_items enable row level security;
alter table public.inventory_stock_movements enable row level security;
alter table public.uniform_requests enable row level security;
alter table public.request_items enable row level security;
alter table public.request_history enable row level security;

create policy employees_authenticated_all
on public.employees
for all
to authenticated
using (true)
with check (true);

create policy employee_import_runs_authenticated_all
on public.employee_import_runs
for all
to authenticated
using (true)
with check (true);

create policy size_chart_authenticated_all
on public.uniform_size_chart
for all
to authenticated
using (true)
with check (true);

create policy inventory_authenticated_all
on public.inventory_items
for all
to authenticated
using (true)
with check (true);

create policy stock_movements_authenticated_all
on public.inventory_stock_movements
for all
to authenticated
using (true)
with check (true);

create policy requests_authenticated_all
on public.uniform_requests
for all
to authenticated
using (true)
with check (true);

create policy request_items_authenticated_all
on public.request_items
for all
to authenticated
using (true)
with check (true);

create policy request_history_authenticated_all
on public.request_history
for all
to authenticated
using (true)
with check (true);

create policy inventory_anon_read
on public.inventory_items
for select
to anon
using (is_active = true);

create policy size_chart_anon_read
on public.uniform_size_chart
for select
to anon
using (true);

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
  ('100005', 'Luca Test', 'luca.test@ikea.com', 'Sales Living Room', 'Co-worker', 'Toronto', 'XS', '28', now())
on conflict (employee_id) do nothing;

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
  ('BOT-PANT-BLU-STR-NA-34-2P', 'Bottoms', 'Pants', 'Blue', 'Straight', 'NA', '2 Pockets', '34', 7, 0, 2, 'Seed from workbook model')
on conflict (sku) do nothing;

insert into public.inventory_stock_movements (
  inventory_item_id,
  qty_delta,
  movement_type,
  reason
)
select id, stock_quantity, 'seed', 'Initial seed quantity'
from public.inventory_items
where not exists (select 1 from public.inventory_stock_movements m where m.inventory_item_id = public.inventory_items.id and m.movement_type = 'seed');

commit;
