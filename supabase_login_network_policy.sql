-- Login and store network policy for Pink Phone CRM
-- Run this after supabase_store_access.sql.

create extension if not exists pgcrypto;

do $$
begin
  create type public.app_role as enum ('대표', '개발자', '점장', '사원');
exception
  when duplicate_object then null;
end
$$;

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
  cleaned := replace(cleaned, '스토어', '');
  cleaned := regexp_replace(cleaned, '점$', '');

  if cleaned = '' then
    return '';
  end if;

  return cleaned || '점';
end;
$$;

create or replace function public.normalize_app_role(input text)
returns public.app_role
language plpgsql
immutable
as $$
declare
  normalized text;
begin
  normalized := coalesce(trim(input), '');

  if normalized in ('대표', '개발자', '점장', '사원') then
    return normalized::public.app_role;
  end if;

  return null;
end;
$$;

create table if not exists public.stores (
  id uuid primary key default gen_random_uuid()
);

alter table public.stores
  add column if not exists name text,
  add column if not exists normalized_name text,
  add column if not exists is_active boolean not null default true,
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists created_at timestamptz not null default timezone('utc', now()),
  add column if not exists updated_at timestamptz not null default timezone('utc', now());

update public.stores
set normalized_name = public.normalize_store_name(coalesce(name, ''))
where coalesce(normalized_name, '') = '';

with ranked_stores as (
  select
    id,
    normalized_name,
    row_number() over (
      partition by normalized_name
      order by created_at asc nulls last, id asc
    ) as rn
  from public.stores
  where coalesce(normalized_name, '') <> ''
),
duplicate_store_map as (
  select
    dup.id as duplicate_id,
    keep.id as keep_id
  from ranked_stores dup
  join ranked_stores keep
    on dup.normalized_name = keep.normalized_name
   and keep.rn = 1
  where dup.rn > 1
)
update public.profiles p
set store_id = m.keep_id
from duplicate_store_map m
where p.store_id = m.duplicate_id;

with ranked_stores as (
  select
    id,
    normalized_name,
    row_number() over (
      partition by normalized_name
      order by created_at asc nulls last, id asc
    ) as rn
  from public.stores
  where coalesce(normalized_name, '') <> ''
),
duplicate_store_map as (
  select
    dup.id as duplicate_id,
    keep.id as keep_id
  from ranked_stores dup
  join ranked_stores keep
    on dup.normalized_name = keep.normalized_name
   and keep.rn = 1
  where dup.rn > 1
)
update public.store_networks n
set store_id = m.keep_id
from duplicate_store_map m
where n.store_id = m.duplicate_id
  and not exists (
    select 1
    from public.store_networks existing
    where existing.store_id = m.keep_id
      and existing.public_ip = n.public_ip
  );

with ranked_stores as (
  select
    id,
    normalized_name,
    row_number() over (
      partition by normalized_name
      order by created_at asc nulls last, id asc
    ) as rn
  from public.stores
  where coalesce(normalized_name, '') <> ''
)
delete from public.store_networks n
using ranked_stores r
where n.store_id = r.id
  and r.rn > 1;

with ranked_stores as (
  select
    id,
    normalized_name,
    row_number() over (
      partition by normalized_name
      order by created_at asc nulls last, id asc
    ) as rn
  from public.stores
  where coalesce(normalized_name, '') <> ''
)
delete from public.stores s
using ranked_stores r
where s.id = r.id
  and r.rn > 1;

create unique index if not exists stores_normalized_name_key
  on public.stores(normalized_name)
  where normalized_name is not null and normalized_name <> '';

create table if not exists public.store_networks (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  public_ip inet not null,
  label text,
  ssid_hint text,
  is_active boolean not null default true,
  registered_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  last_seen_at timestamptz
);

create unique index if not exists store_networks_store_ip_key
  on public.store_networks(store_id, public_ip);

create index if not exists store_networks_store_active_idx
  on public.store_networks(store_id, is_active);

create table if not exists public.store_network_requests (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  public_ip inet not null,
  label text,
  ssid_hint text,
  wifi_ip inet,
  wifi_gateway_ip inet,
  wifi_bssid text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_by uuid references public.profiles(id) on delete set null,
  reviewed_by uuid references public.profiles(id) on delete set null,
  requested_at timestamptz not null default timezone('utc', now()),
  reviewed_at timestamptz,
  updated_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists store_network_requests_pending_key
  on public.store_network_requests(store_id, public_ip, status)
  where status = 'pending';

create index if not exists store_network_requests_store_status_idx
  on public.store_network_requests(store_id, status, requested_at desc);

alter table public.profiles
  add column if not exists role_code public.app_role,
  add column if not exists store_id uuid references public.stores(id) on delete set null,
  add column if not exists last_login_platform text,
  add column if not exists last_login_public_ip inet,
  add column if not exists last_login_at timestamptz,
  add column if not exists login_policy_message text;

insert into public.stores (name, normalized_name, is_active)
select distinct
  public.normalize_store_name(p.store),
  public.normalize_store_name(p.store),
  true
from public.profiles p
where coalesce(trim(p.store), '') <> ''
  and public.normalize_store_name(p.store) <> ''
  and not exists (
    select 1
    from public.stores s
    where s.normalized_name = public.normalize_store_name(p.store)
  );

update public.profiles p
set role_code = public.normalize_app_role(p.role)
where p.role_code is null
  and public.normalize_app_role(p.role) is not null;

update public.profiles p
set store_id = s.id
from public.stores s
where p.store_id is null
  and public.normalize_store_name(p.store) = s.normalized_name;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists stores_set_updated_at on public.stores;
create trigger stores_set_updated_at
before update on public.stores
for each row execute function public.set_updated_at();

drop trigger if exists store_networks_set_updated_at on public.store_networks;
create trigger store_networks_set_updated_at
before update on public.store_networks
for each row execute function public.set_updated_at();

drop trigger if exists store_network_requests_set_updated_at on public.store_network_requests;
create trigger store_network_requests_set_updated_at
before update on public.store_network_requests
for each row execute function public.set_updated_at();

create or replace function public.current_profile_role_text()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(role_code::text, role)
  from public.profiles
  where id = auth.uid()
  limit 1
$$;

create or replace function public.current_profile_store_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select store_id
  from public.profiles
  where id = auth.uid()
  limit 1
$$;

create or replace function public.current_profile_has_role(allowed_roles text[])
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
      and approval_status = 'approved'
      and coalesce(role_code::text, role) = any(allowed_roles)
  )
$$;

create or replace function public.current_profile_is_privileged()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_profile_has_role(array['대표', '개발자'])
$$;

create or replace function public.current_profile_is_manager()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_profile_has_role(array['점장'])
$$;

create or replace function public.current_profile_can_manage_store_networks(target_store_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.current_profile_is_privileged()
    or (
      public.current_profile_is_manager()
      and (
        target_store_id is null
        or target_store_id = public.current_profile_store_id()
      )
    )
$$;

alter table public.stores enable row level security;
alter table public.store_networks enable row level security;
alter table public.store_network_requests enable row level security;

drop policy if exists stores_select_policy on public.stores;
create policy stores_select_policy on public.stores
for select
to authenticated
using (
  public.current_profile_is_privileged()
  or id = public.current_profile_store_id()
);

drop policy if exists stores_manage_policy on public.stores;
create policy stores_manage_policy on public.stores
for all
to authenticated
using (public.current_profile_is_privileged())
with check (public.current_profile_is_privileged());

drop policy if exists store_networks_select_policy on public.store_networks;
create policy store_networks_select_policy on public.store_networks
for select
to authenticated
using (public.current_profile_can_manage_store_networks(store_id));

drop policy if exists store_networks_insert_policy on public.store_networks;
create policy store_networks_insert_policy on public.store_networks
for insert
to authenticated
with check (public.current_profile_is_privileged());

drop policy if exists store_networks_update_policy on public.store_networks;
create policy store_networks_update_policy on public.store_networks
for update
to authenticated
using (public.current_profile_can_manage_store_networks(store_id))
with check (public.current_profile_is_privileged());

drop policy if exists store_networks_delete_policy on public.store_networks;
create policy store_networks_delete_policy on public.store_networks
for delete
to authenticated
using (public.current_profile_is_privileged());

drop policy if exists store_network_requests_select_policy on public.store_network_requests;
create policy store_network_requests_select_policy on public.store_network_requests
for select
to authenticated
using (public.current_profile_can_manage_store_networks(store_id));

drop policy if exists store_network_requests_insert_policy on public.store_network_requests;
create policy store_network_requests_insert_policy on public.store_network_requests
for insert
to authenticated
with check (public.current_profile_can_manage_store_networks(store_id));

drop policy if exists store_network_requests_update_policy on public.store_network_requests;
create policy store_network_requests_update_policy on public.store_network_requests
for update
to authenticated
using (public.current_profile_is_privileged())
with check (public.current_profile_is_privileged());

drop policy if exists store_network_requests_delete_policy on public.store_network_requests;
create policy store_network_requests_delete_policy on public.store_network_requests
for delete
to authenticated
using (public.current_profile_is_privileged());
