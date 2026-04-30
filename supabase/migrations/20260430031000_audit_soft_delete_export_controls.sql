-- Audit log hardening, soft-delete recycle bin columns, and export logging support.

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_table text not null,
  target_id text,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists audit_logs_created_at_idx on public.audit_logs(created_at desc);
create index if not exists audit_logs_target_idx on public.audit_logs(target_table, target_id);
create index if not exists audit_logs_actor_idx on public.audit_logs(actor_id, created_at desc);

alter table public.audit_logs enable row level security;

drop policy if exists audit_logs_privileged_select on public.audit_logs;
create policy audit_logs_privileged_select on public.audit_logs
for select
to authenticated
using (public.current_profile_is_privileged());

drop policy if exists audit_logs_actor_insert on public.audit_logs;
create policy audit_logs_actor_insert on public.audit_logs
for insert
to authenticated
with check (
  actor_id = auth.uid()
  and public.current_profile_has_role(array['대표', '개발자', '점장', '사원'])
);

alter table public.customers
  add column if not exists is_deleted boolean not null default false,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null;

alter table public.leads
  add column if not exists is_deleted boolean not null default false,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null;

alter table public.wired_members
  add column if not exists is_deleted boolean not null default false,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null;

alter table public.device_inventory
  add column if not exists is_deleted boolean not null default false,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null;

create index if not exists customers_is_deleted_idx on public.customers(is_deleted, normalized_store);
create index if not exists leads_is_deleted_idx on public.leads(is_deleted, normalized_store);
create index if not exists wired_members_is_deleted_idx on public.wired_members(is_deleted, normalized_store);
create index if not exists device_inventory_is_deleted_idx on public.device_inventory(is_deleted, normalized_store);

-- Prevent legacy clients from permanently deleting sensitive CRM records.
drop policy if exists customers_store_delete on public.customers;
drop policy if exists leads_store_delete on public.leads;
drop policy if exists wired_members_store_delete on public.wired_members;
drop policy if exists device_inventory_store_delete on public.device_inventory;

-- Only active records are visible in normal screens. Deleted rows remain recoverable by privileged users through future admin tooling.
drop policy if exists customers_store_select on public.customers;
create policy customers_store_select on public.customers
for select
to authenticated
using (
  is_deleted = false
  and (
    public.current_profile_is_privileged()
    or (
      public.current_profile_can_edit_store_records()
      and normalized_store = public.current_profile_store()
    )
  )
);

drop policy if exists leads_store_select on public.leads;
create policy leads_store_select on public.leads
for select
to authenticated
using (
  is_deleted = false
  and (
    public.current_profile_is_privileged()
    or (
      public.current_profile_can_edit_store_records()
      and normalized_store = public.current_profile_store()
    )
  )
);

drop policy if exists wired_members_store_select on public.wired_members;
create policy wired_members_store_select on public.wired_members
for select
to authenticated
using (
  is_deleted = false
  and (
    public.current_profile_is_privileged()
    or (
      public.current_profile_can_edit_store_records()
      and normalized_store = public.current_profile_store()
    )
  )
);

drop policy if exists device_inventory_store_select on public.device_inventory;
create policy device_inventory_store_select on public.device_inventory
for select
to authenticated
using (
  is_deleted = false
  and (
    public.current_profile_is_privileged()
    or (
      public.current_profile_can_manage_inventory()
      and normalized_store = public.current_profile_store()
    )
  )
);

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
  where c.is_deleted = false
    and c.normalized_store = public.current_profile_store()
  order by c.join_date asc nulls last, c.created_at asc nulls last;
end;
$$;

grant execute on function public.customer_open_rows() to authenticated;

create or replace function public.audit_crm_row_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_logs(actor_id, action, target_table, target_id, detail)
  values (
    auth.uid(),
    lower(tg_op) || '_' || tg_table_name,
    tg_table_name,
    coalesce(new.id::text, old.id::text),
    jsonb_build_object(
      'old', case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
      'new', case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
    )
  );
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists audit_customers_changes on public.customers;
create trigger audit_customers_changes
after insert or update on public.customers
for each row execute function public.audit_crm_row_change();

drop trigger if exists audit_leads_changes on public.leads;
create trigger audit_leads_changes
after insert or update on public.leads
for each row execute function public.audit_crm_row_change();

drop trigger if exists audit_wired_members_changes on public.wired_members;
create trigger audit_wired_members_changes
after insert or update on public.wired_members
for each row execute function public.audit_crm_row_change();

drop trigger if exists audit_device_inventory_changes on public.device_inventory;
create trigger audit_device_inventory_changes
after insert or update on public.device_inventory
for each row execute function public.audit_crm_row_change();

drop trigger if exists audit_profiles_changes on public.profiles;
create trigger audit_profiles_changes
after update or delete on public.profiles
for each row execute function public.audit_crm_row_change();

create or replace function public.crm_deleted_records()
returns table (
  target_table text,
  target_id text,
  store text,
  title text,
  subtitle text,
  deleted_at timestamptz,
  deleted_by uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select * from (
    select 'customers'::text, id::text, store::text, coalesce(name::text, '-') as title,
      coalesce(phone::text, '') as subtitle, deleted_at, deleted_by
    from public.customers
    where is_deleted = true
    union all
    select 'leads'::text, id::text, store::text, coalesce(subscriber::text, '-') as title,
      coalesce(phone::text, '') as subtitle, deleted_at, deleted_by
    from public.leads
    where is_deleted = true
    union all
    select 'wired_members'::text, id::text, store::text, coalesce(subscriber::text, '-') as title,
      coalesce(phone::text, '') as subtitle, deleted_at, deleted_by
    from public.wired_members
    where is_deleted = true
    union all
    select 'device_inventory'::text, id::text, store::text, coalesce(model_name::text, '-') as title,
      coalesce(serial_number::text, '') as subtitle, deleted_at, deleted_by
    from public.device_inventory
    where is_deleted = true
  ) rows
  where public.current_profile_is_privileged()
  order by deleted_at desc nulls last
  limit 200
$$;

create or replace function public.restore_crm_record(target_table text, target_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.current_profile_is_privileged() then
    raise exception 'permission denied';
  end if;

  if target_table not in ('customers', 'leads', 'wired_members', 'device_inventory') then
    raise exception 'invalid target table';
  end if;

  execute format(
    'update public.%I set is_deleted = false, deleted_at = null, deleted_by = null where id::text = $1',
    target_table
  ) using target_id;

  insert into public.audit_logs(actor_id, action, target_table, target_id, detail)
  values (auth.uid(), 'restore_' || target_table, target_table, target_id, '{}'::jsonb);
end;
$$;

grant execute on function public.crm_deleted_records() to authenticated;
grant execute on function public.restore_crm_record(text, text) to authenticated;
