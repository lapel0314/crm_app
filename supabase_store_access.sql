-- CRM role and store access policies
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
  cleaned := replace(cleaned, '스토어', '');
  cleaned := regexp_replace(cleaned, '점$', '');

  if cleaned = '' then
    return '';
  end if;

  return cleaned || '점';
end;
$$;

create or replace function public.current_profile_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role
  from public.profiles
  where id = auth.uid()
    and approval_status = 'approved'
  limit 1
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
    and approval_status = 'approved'
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
      and role = any(allowed_roles)
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

create or replace function public.current_profile_is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_profile_has_role(array['사원'])
$$;

create or replace function public.current_profile_can_edit_store_records()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_profile_has_role(array['대표', '개발자', '점장', '사원'])
$$;

create or replace function public.current_profile_can_delete_store_records()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_profile_has_role(array['대표', '개발자', '점장'])
$$;

create or replace function public.current_profile_can_manage_inventory()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_profile_has_role(array['대표', '개발자', '점장'])
$$;

alter table public.profiles
  add column if not exists normalized_store text generated always as (public.normalize_store_name(store)) stored;

alter table public.customers
  add column if not exists normalized_store text generated always as (public.normalize_store_name(store)) stored;

alter table public.customers
  add column if not exists kakao_chat_type text default 'friend'
    check (kakao_chat_type in ('friend', 'group', 'openChat')),
  add column if not exists kakao_room_name text,
  add column if not exists kakao_search_name text;

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
  or (
    public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists customers_store_insert on public.customers;
create policy customers_store_insert on public.customers
for insert
to authenticated
with check (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists customers_store_update on public.customers;
create policy customers_store_update on public.customers
for update
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
)
with check (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists customers_store_delete on public.customers;
create policy customers_store_delete on public.customers
for delete
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_delete_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists leads_store_select on public.leads;
create policy leads_store_select on public.leads
for select
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists leads_store_insert on public.leads;
create policy leads_store_insert on public.leads
for insert
to authenticated
with check (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists leads_store_update on public.leads;
create policy leads_store_update on public.leads
for update
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
)
with check (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists leads_store_delete on public.leads;
create policy leads_store_delete on public.leads
for delete
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_delete_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists wired_members_store_select on public.wired_members;
create policy wired_members_store_select on public.wired_members
for select
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists wired_members_store_insert on public.wired_members;
create policy wired_members_store_insert on public.wired_members
for insert
to authenticated
with check (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists wired_members_store_update on public.wired_members;
create policy wired_members_store_update on public.wired_members
for update
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
)
with check (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists wired_members_store_delete on public.wired_members;
create policy wired_members_store_delete on public.wired_members
for delete
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_delete_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists device_inventory_store_select on public.device_inventory;
create policy device_inventory_store_select on public.device_inventory
for select
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_manage_inventory()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists device_inventory_store_insert on public.device_inventory;
create policy device_inventory_store_insert on public.device_inventory
for insert
to authenticated
with check (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_manage_inventory()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists device_inventory_store_update on public.device_inventory;
create policy device_inventory_store_update on public.device_inventory
for update
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_manage_inventory()
    and normalized_store = public.current_profile_store()
  )
)
with check (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_manage_inventory()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists device_inventory_store_delete on public.device_inventory;
create policy device_inventory_store_delete on public.device_inventory
for delete
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_can_manage_inventory()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists profiles_store_select on public.profiles;
create policy profiles_store_select on public.profiles
for select
to authenticated
using (
  id = auth.uid()
  or public.current_profile_is_privileged()
  or (
    public.current_profile_has_role(array['점장', '사원'])
    and normalized_store = public.current_profile_store()
    and approval_status = 'approved'
  )
);

drop policy if exists profiles_privileged_update on public.profiles;
create policy profiles_privileged_update on public.profiles
for update
to authenticated
using (public.current_profile_is_privileged())
with check (public.current_profile_is_privileged());

drop policy if exists profiles_privileged_delete on public.profiles;
create policy profiles_privileged_delete on public.profiles
for delete
to authenticated
using (public.current_profile_is_privileged());

create or replace function public.mask_name(input text)
returns text
language sql
immutable
as $$
  select case
    when coalesce(input, '') = '' then ''
    when char_length(input) = 1 then '*'
    when char_length(input) = 2 then substring(input from 1 for 1) || '*'
    else substring(input from 1 for 1) || repeat('*', greatest(char_length(input) - 2, 0)) || substring(input from char_length(input) for 1)
  end
$$;

create or replace function public.mask_phone(input text)
returns text
language sql
immutable
as $$
  select case
    when regexp_replace(coalesce(input, ''), '[^0-9]', '', 'g') ~ '^.{11}$'
      then substring(regexp_replace(input, '[^0-9]', '', 'g') from 1 for 3) || '-****-' || substring(regexp_replace(input, '[^0-9]', '', 'g') from 8 for 4)
    else coalesce(input, '')
  end
$$;

create or replace function public.mask_bank_info(input text)
returns text
language sql
immutable
as $$
  select case
    when coalesce(trim(input), '') = '' then ''
    when char_length(input) <= 4 then '****'
    else substring(input from 1 for 2) || '****' || substring(input from char_length(input) - 1 for 2)
  end
$$;

create or replace function public.customer_open_rows()
returns table (
  id text,
  join_date text,
  created_at text,
  m3 text,
  m6 text,
  staff text,
  name text,
  phone text,
  join_type text,
  carrier text,
  previous_carrier text,
  model text,
  plan text,
  add_service text,
  contract_type text,
  installment text,
  rebate text,
  add_rebate text,
  hidden_rebate text,
  hidden_note text,
  deduction text,
  deduction_note text,
  support_money text,
  payment text,
  payment_note text,
  deposit text,
  bank_info text,
  trade_in boolean,
  trade_model text,
  trade_price text,
  total_rebate text,
  tax text,
  margin text,
  memo text,
  store text,
  mobile text,
  second text,
  kakao_chat_type text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.current_profile_has_role(array['조회용']) then
    return;
  end if;

  return query
  select
    c.id::text,
    c.join_date::text,
    c.created_at::text,
    c.m3::text,
    c.m6::text,
    c.staff::text,
    public.mask_name(c.name::text),
    public.mask_phone(c.phone::text),
    c.join_type::text,
    c.carrier::text,
    c.previous_carrier::text,
    c.model::text,
    c.plan::text,
    c.add_service::text,
    c.contract_type::text,
    c.installment::text,
    c.rebate::text,
    c.add_rebate::text,
    c.hidden_rebate::text,
    c.hidden_note::text,
    c.deduction::text,
    c.deduction_note::text,
    c.support_money::text,
    c.payment::text,
    c.payment_note::text,
    c.deposit::text,
    public.mask_bank_info(c.bank_info::text),
    c.trade_in,
    c.trade_model::text,
    c.trade_price::text,
    c.total_rebate::text,
    c.tax::text,
    c.margin::text,
    c.memo::text,
    c.store::text,
    c.mobile::text,
    c.second::text,
    c.kakao_chat_type::text
  from public.customers c
  where c.normalized_store = public.current_profile_store()
  order by c.join_date asc nulls last, c.created_at asc nulls last;
end;
$$;

grant execute on function public.customer_open_rows() to authenticated;

do $$
begin
  if to_regclass('public.audit_logs') is not null then
    execute 'alter table public.audit_logs enable row level security';

    execute 'drop policy if exists audit_logs_privileged_select on public.audit_logs';
    execute 'create policy audit_logs_privileged_select on public.audit_logs
      for select
      to authenticated
      using (public.current_profile_is_privileged())';

    execute 'drop policy if exists audit_logs_actor_insert on public.audit_logs';
    execute 'create policy audit_logs_actor_insert on public.audit_logs
      for insert
      to authenticated
      with check (
        actor_id = auth.uid()
        and public.current_profile_has_role(array[''대표'', ''개발자'', ''점장'', ''사원''])
      )';
  end if;
end;
$$;
