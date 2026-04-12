-- Store-level access helpers and policies for Pink Phone CRM.
-- Run this in the Supabase SQL Editor after backing up the project.

create or replace function public.normalize_store_name(input text)
returns text
language plpgsql
immutable
as $$
declare
  cleaned text;
begin
  cleaned := coalesce(trim(input), '');
  if cleaned = '' then
    return '';
  end if;

  cleaned := regexp_replace(cleaned, '\s+', '', 'g');
  cleaned := replace(cleaned, '매장', '');
  cleaned := replace(cleaned, '지점', '');
  cleaned := replace(cleaned, '점포', '');
  cleaned := regexp_replace(cleaned, '점+$', '');

  if cleaned = '' then
    return '';
  end if;

  return cleaned || '점';
end;
$$;

create or replace function public.current_profile_store()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select public.normalize_store_name(store)
  from public.profiles
  where id = auth.uid()
  limit 1
$$;

create or replace function public.current_profile_is_privileged()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role in ('대표', '개발자')
  )
$$;

alter table public.profiles
  add column if not exists normalized_store text generated always as (public.normalize_store_name(store)) stored;

alter table public.customers
  add column if not exists normalized_store text generated always as (public.normalize_store_name(store)) stored;

alter table public.leads
  add column if not exists store text,
  add column if not exists normalized_store text generated always as (public.normalize_store_name(store)) stored;

alter table public.wired_members
  add column if not exists store text,
  add column if not exists normalized_store text generated always as (public.normalize_store_name(store)) stored;

alter table public.device_inventory
  add column if not exists normalized_store text generated always as (public.normalize_store_name(store)) stored;

create index if not exists profiles_normalized_store_idx on public.profiles(normalized_store);
create index if not exists customers_normalized_store_idx on public.customers(normalized_store);
create index if not exists leads_normalized_store_idx on public.leads(normalized_store);
create index if not exists wired_members_normalized_store_idx on public.wired_members(normalized_store);
create index if not exists device_inventory_normalized_store_idx on public.device_inventory(normalized_store);

alter table public.customers enable row level security;
alter table public.leads enable row level security;
alter table public.wired_members enable row level security;
alter table public.device_inventory enable row level security;
alter table public.profiles enable row level security;

drop policy if exists customers_store_select on public.customers;
create policy customers_store_select on public.customers
for select
to authenticated
using (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists customers_store_insert on public.customers;
create policy customers_store_insert on public.customers
for insert
to authenticated
with check (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists customers_store_update on public.customers;
create policy customers_store_update on public.customers
for update
to authenticated
using (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
)
with check (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists customers_store_delete on public.customers;
create policy customers_store_delete on public.customers
for delete
to authenticated
using (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists leads_store_select on public.leads;
create policy leads_store_select on public.leads
for select
to authenticated
using (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists leads_store_insert on public.leads;
create policy leads_store_insert on public.leads
for insert
to authenticated
with check (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists leads_store_update on public.leads;
create policy leads_store_update on public.leads
for update
to authenticated
using (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
)
with check (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists leads_store_delete on public.leads;
create policy leads_store_delete on public.leads
for delete
to authenticated
using (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists wired_members_store_select on public.wired_members;
create policy wired_members_store_select on public.wired_members
for select
to authenticated
using (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists wired_members_store_insert on public.wired_members;
create policy wired_members_store_insert on public.wired_members
for insert
to authenticated
with check (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists wired_members_store_update on public.wired_members;
create policy wired_members_store_update on public.wired_members
for update
to authenticated
using (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
)
with check (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists wired_members_store_delete on public.wired_members;
create policy wired_members_store_delete on public.wired_members
for delete
to authenticated
using (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists device_inventory_store_select on public.device_inventory;
create policy device_inventory_store_select on public.device_inventory
for select
to authenticated
using (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists device_inventory_store_insert on public.device_inventory;
create policy device_inventory_store_insert on public.device_inventory
for insert
to authenticated
with check (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists device_inventory_store_update on public.device_inventory;
create policy device_inventory_store_update on public.device_inventory
for update
to authenticated
using (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
)
with check (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists device_inventory_store_delete on public.device_inventory;
create policy device_inventory_store_delete on public.device_inventory
for delete
to authenticated
using (
  public.current_profile_is_privileged()
  or normalized_store = public.current_profile_store()
);

drop policy if exists profiles_store_select on public.profiles;
create policy profiles_store_select on public.profiles
for select
to authenticated
using (
  id = auth.uid()
  or (
    role not in ('대표', '개발자')
    and (
      public.current_profile_is_privileged()
      or normalized_store = public.current_profile_store()
    )
  )
);
