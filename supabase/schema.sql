
-- uniform_portal_schema.sql
-- Reset + full schema for Uniform Portal
-- PostgreSQL / Supabase compatible

begin;

create extension if not exists pgcrypto;

-- Optional: clean reset
drop table if exists public.request_status_history cascade;
drop table if exists public.uniform_requests cascade;
drop table if exists public.inventory_items cascade;
drop table if exists public.employee_directory cascade;
drop table if exists public.profiles cascade;

-- =========================
-- PROFILES (admins/users)
-- =========================
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text unique,
  role text not null default 'employee' check (role in ('employee', 'admin', 'pc_admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- =========================
-- EMPLOYEE DIRECTORY
-- Centralized employee list
-- =========================
create table public.employee_directory (
  id uuid primary key default gen_random_uuid(),
  employee_id text not null unique,
  full_name text not null,
  email text not null unique,
  department text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employee_email_ikea_chk check (
    position('@' in email) > 1
  )
);

create index employee_directory_employee_id_idx on public.employee_directory(employee_id);
create index employee_directory_email_idx on public.employee_directory(lower(email));

-- =========================
-- INVENTORY ITEMS
-- =========================
create table public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  sku text unique,
  product_type text not null,
  style text,
  colour text,
  fit text,
  sleeve text,
  size text not null,
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  reorder_level integer not null default 5 check (reorder_level >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index inventory_items_lookup_idx
  on public.inventory_items(product_type, style, colour, size);

-- =========================
-- UNIFORM REQUESTS
-- =========================
create table public.uniform_requests (
  id uuid primary key default gen_random_uuid(),

  -- employee info (snapshotted from employee_directory)
  employee_directory_id uuid references public.employee_directory(id) on delete set null,
  employee_id text not null,
  employee_name text not null,
  employee_email text not null,
  department text,

  -- request details
  product_type text not null,
  style text,
  colour text,
  fit text,
  sleeve text,
  requested_size text not null,
  suggested_size text,
  special_request_note text,

  inventory_item_id uuid references public.inventory_items(id) on delete set null,

  -- workflow
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'ordered', 'completed', 'cancelled', 'special_request')),
  stock_reserved integer not null default 0 check (stock_reserved >= 0),
  admin_note text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index uniform_requests_status_idx on public.uniform_requests(status);
create index uniform_requests_created_at_idx on public.uniform_requests(created_at desc);
create index uniform_requests_employee_id_idx on public.uniform_requests(employee_id);
create index uniform_requests_product_size_idx on public.uniform_requests(product_type, requested_size);

-- =========================
-- STATUS HISTORY LOG
-- Full audit of co-worker requests
-- =========================
create table public.request_status_history (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.uniform_requests(id) on delete cascade,
  old_status text,
  new_status text not null,
  changed_by uuid references public.profiles(id) on delete set null,
  note text,
  created_at timestamptz not null default now()
);

create index request_status_history_request_id_idx
  on public.request_status_history(request_id, created_at desc);

-- =========================
-- updated_at helper
-- =========================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger set_profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger set_employee_directory_updated_at
before update on public.employee_directory
for each row execute function public.set_updated_at();

create trigger set_inventory_items_updated_at
before update on public.inventory_items
for each row execute function public.set_updated_at();

create trigger set_uniform_requests_updated_at
before update on public.uniform_requests
for each row execute function public.set_updated_at();

-- =========================
-- Admin helper function
-- =========================
create or replace function public.is_admin(user_id uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = user_id
      and p.role in ('admin', 'pc_admin')
  );
$$;

-- =========================
-- Create profile on signup
-- =========================
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
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.email,
    'employee'
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- =========================
-- Employee autofill helpers
-- =========================
create or replace function public.get_employee_by_employee_id(p_employee_id text)
returns table (
  id uuid,
  employee_id text,
  full_name text,
  email text,
  department text,
  is_active boolean
)
language sql
security definer
set search_path = public
as $$
  select
    ed.id,
    ed.employee_id,
    ed.full_name,
    ed.email,
    ed.department,
    ed.is_active
  from public.employee_directory ed
  where ed.employee_id = p_employee_id
    and ed.is_active = true
  limit 1;
$$;

create or replace function public.get_employee_by_email(p_email text)
returns table (
  id uuid,
  employee_id text,
  full_name text,
  email text,
  department text,
  is_active boolean
)
language sql
security definer
set search_path = public
as $$
  select
    ed.id,
    ed.employee_id,
    ed.full_name,
    ed.email,
    ed.department,
    ed.is_active
  from public.employee_directory ed
  where lower(ed.email) = lower(p_email)
    and ed.is_active = true
  limit 1;
$$;

-- =========================
-- Request submit function
-- Handles stock reservation + employee snapshot
-- =========================
create or replace function public.submit_uniform_request(
  p_employee_id text,
  p_product_type text,
  p_style text default null,
  p_colour text default null,
  p_fit text default null,
  p_sleeve text default null,
  p_requested_size text default null,
  p_suggested_size text default null,
  p_special_request_note text default null
)
returns public.uniform_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee public.employee_directory%rowtype;
  v_inventory public.inventory_items%rowtype;
  v_request public.uniform_requests%rowtype;
  v_status text;
  v_reserved integer := 0;
begin
  select *
    into v_employee
  from public.employee_directory
  where employee_id = p_employee_id
    and is_active = true
  limit 1;

  if v_employee.id is null then
    raise exception 'Employee not found or inactive';
  end if;

  select *
    into v_inventory
  from public.inventory_items
  where product_type = p_product_type
    and coalesce(style, '') = coalesce(p_style, '')
    and coalesce(colour, '') = coalesce(p_colour, '')
    and coalesce(fit, '') = coalesce(p_fit, '')
    and coalesce(sleeve, '') = coalesce(p_sleeve, '')
    and size = p_requested_size
    and is_active = true
  limit 1
  for update;

  if v_inventory.id is not null and v_inventory.stock_quantity > 0 then
    v_status := 'pending';
    v_reserved := 1;

    update public.inventory_items
      set stock_quantity = stock_quantity - 1
    where id = v_inventory.id;
  elsif p_special_request_note is not null and length(trim(p_special_request_note)) > 0 then
    v_status := 'special_request';
  else
    v_status := 'pending';
  end if;

  insert into public.uniform_requests (
    employee_directory_id,
    employee_id,
    employee_name,
    employee_email,
    department,
    product_type,
    style,
    colour,
    fit,
    sleeve,
    requested_size,
    suggested_size,
    special_request_note,
    inventory_item_id,
    status,
    stock_reserved
  )
  values (
    v_employee.id,
    v_employee.employee_id,
    v_employee.full_name,
    v_employee.email,
    v_employee.department,
    p_product_type,
    p_style,
    p_colour,
    p_fit,
    p_sleeve,
    p_requested_size,
    p_suggested_size,
    p_special_request_note,
    v_inventory.id,
    v_status,
    v_reserved
  )
  returning * into v_request;

  insert into public.request_status_history (
    request_id,
    old_status,
    new_status,
    changed_by,
    note
  )
  values (
    v_request.id,
    null,
    v_request.status,
    auth.uid(),
    'Request created'
  );

  return v_request;
end;
$$;

-- =========================
-- Status update function
-- Keeps inventory consistent
-- =========================
create or replace function public.update_request_status(
  p_request_id uuid,
  p_new_status text,
  p_admin_note text default null
)
returns public.uniform_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.uniform_requests%rowtype;
  v_result public.uniform_requests%rowtype;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Only admins can update request status';
  end if;

  select *
    into v_request
  from public.uniform_requests
  where id = p_request_id
  for update;

  if v_request.id is null then
    raise exception 'Request not found';
  end if;

  if v_request.status = p_new_status then
    update public.uniform_requests
      set admin_note = coalesce(p_admin_note, admin_note)
    where id = p_request_id
    returning * into v_result;

    return v_result;
  end if;

  -- release reserved stock when cancelled
  if p_new_status = 'cancelled'
     and v_request.stock_reserved > 0
     and v_request.inventory_item_id is not null then
    update public.inventory_items
      set stock_quantity = stock_quantity + v_request.stock_reserved
    where id = v_request.inventory_item_id;

    update public.uniform_requests
      set stock_reserved = 0,
          status = p_new_status,
          admin_note = p_admin_note
    where id = p_request_id
    returning * into v_result;
  else
    update public.uniform_requests
      set status = p_new_status,
          admin_note = p_admin_note
    where id = p_request_id
    returning * into v_result;
  end if;

  insert into public.request_status_history (
    request_id,
    old_status,
    new_status,
    changed_by,
    note
  )
  values (
    v_request.id,
    v_request.status,
    p_new_status,
    auth.uid(),
    p_admin_note
  );

  return v_result;
end;
$$;

-- =========================
-- ANALYTICS VIEWS
-- =========================
create or replace view public.analytics_requested_sizes as
select
  requested_size,
  count(*) as total_requests
from public.uniform_requests
group by requested_size
order by total_requests desc, requested_size;

create or replace view public.analytics_most_ordered_items as
select
  product_type,
  coalesce(style, '') as style,
  coalesce(colour, '') as colour,
  requested_size,
  count(*) as total_requests
from public.uniform_requests
group by product_type, coalesce(style, ''), coalesce(colour, ''), requested_size
order by total_requests desc, product_type;

create or replace view public.analytics_requests_by_status as
select
  status,
  count(*) as total_requests
from public.uniform_requests
group by status
order by total_requests desc;

create or replace view public.analytics_low_stock_items as
select
  id,
  sku,
  product_type,
  style,
  colour,
  size,
  stock_quantity,
  reorder_level
from public.inventory_items
where is_active = true
  and stock_quantity <= reorder_level
order by stock_quantity asc, product_type;

-- =========================
-- Row Level Security
-- =========================
alter table public.profiles enable row level security;
alter table public.employee_directory enable row level security;
alter table public.inventory_items enable row level security;
alter table public.uniform_requests enable row level security;
alter table public.request_status_history enable row level security;

-- PROFILES
create policy "profiles_select_own_or_admin"
on public.profiles
for select
to authenticated
using (auth.uid() = id or public.is_admin(auth.uid()));

create policy "profiles_update_own_or_admin"
on public.profiles
for update
to authenticated
using (auth.uid() = id or public.is_admin(auth.uid()))
with check (auth.uid() = id or public.is_admin(auth.uid()));

-- EMPLOYEE DIRECTORY
create policy "employee_directory_select_authenticated"
on public.employee_directory
for select
to authenticated
using (true);

create policy "employee_directory_admin_all"
on public.employee_directory
for all
to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

-- INVENTORY
create policy "inventory_select_authenticated"
on public.inventory_items
for select
to authenticated
using (true);

create policy "inventory_admin_all"
on public.inventory_items
for all
to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

-- REQUESTS
create policy "requests_select_own_or_admin"
on public.uniform_requests
for select
to authenticated
using (
  public.is_admin(auth.uid())
  or lower(employee_email) = lower(coalesce((select email from auth.users where id = auth.uid()), ''))
);

create policy "requests_insert_authenticated"
on public.uniform_requests
for insert
to authenticated
with check (true);

create policy "requests_update_admin_only"
on public.uniform_requests
for update
to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

-- HISTORY
create policy "history_select_admin_only"
on public.request_status_history
for select
to authenticated
using (public.is_admin(auth.uid()));

create policy "history_insert_admin_or_authenticated"
on public.request_status_history
for insert
to authenticated
with check (public.is_admin(auth.uid()) or auth.uid() is not null);

-- =========================
-- Seed example admin
-- Replace the UUID/email after creating the first auth user
-- =========================
-- update public.profiles
-- set role = 'admin'
-- where email = 'your-admin@ikea.com';

commit;
