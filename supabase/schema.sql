begin;

create extension if not exists pgcrypto;

drop schema if exists public cascade;
create schema public;

grant usage on schema public to postgres, anon, authenticated, service_role;
grant create on schema public to postgres, service_role;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

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
  inventory_key text not null unique,
  sku text unique,
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
create index idx_inventory_lookup on public.inventory_items(product_type, fit, size);
create index idx_uniform_requests_status on public.uniform_requests(status, created_at desc);
create index idx_request_items_request_id on public.request_items(request_id);
create index idx_request_history_request_id on public.request_history(request_id, created_at desc);

create trigger trg_employees_updated_at
before update on public.employees
for each row execute procedure public.set_updated_at();

create trigger trg_inventory_items_updated_at
before update on public.inventory_items
for each row execute procedure public.set_updated_at();

create trigger trg_uniform_requests_updated_at
before update on public.uniform_requests
for each row execute procedure public.set_updated_at();

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
    when 'ONE SIZE' then 90
    when 'C-J' then 91
    when 'K-Y' then 92
    when '55-58' then 93
    when '58-61' then 94
    when '55' then 95
    when '58' then 96
    when '61' then 97
    else 999
  end;
$$;

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
       and coalesce(colour, '') = coalesce(v_item.colour, '')
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
         admin_notes = coalesce(p_message, admin_notes)
   where id = p_request_id
   returning * into v_request;

  insert into public.request_history (request_id, action, old_status, new_status, message, changed_by)
  values (
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

alter table public.employees enable row level security;
alter table public.uniform_size_chart enable row level security;
alter table public.inventory_items enable row level security;
alter table public.inventory_stock_movements enable row level security;
alter table public.uniform_requests enable row level security;
alter table public.request_items enable row level security;
alter table public.request_history enable row level security;

create policy employees_authenticated_all on public.employees for all to authenticated using (true) with check (true);
create policy size_chart_authenticated_all on public.uniform_size_chart for all to authenticated using (true) with check (true);
create policy inventory_authenticated_all on public.inventory_items for all to authenticated using (true) with check (true);
create policy stock_movements_authenticated_all on public.inventory_stock_movements for all to authenticated using (true) with check (true);
create policy requests_authenticated_all on public.uniform_requests for all to authenticated using (true) with check (true);
create policy request_items_authenticated_all on public.request_items for all to authenticated using (true) with check (true);
create policy request_history_authenticated_all on public.request_history for all to authenticated using (true) with check (true);

create policy inventory_anon_read on public.inventory_items for select to anon using (is_active = true);
create policy size_chart_anon_read on public.uniform_size_chart for select to anon using (true);

commit;
