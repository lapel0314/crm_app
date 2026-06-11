-- Security hardening for network-bound reads, update package integrity,
-- client audit logging, and profile mutations.

create or replace function public.current_profile_has_fresh_network_session(ttl interval default interval '2 minutes')
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select
      case
        when coalesce(p.role_code::text, p.role) not in ('사원', '조회용') then true
        when p.approval_status <> 'approved' then false
        when p.store_id is null then false
        when p.last_login_at is null or p.last_login_at < timezone('utc', now()) - ttl then false
        when p.last_login_public_ip is null then false
        else exists (
          select 1
          from public.store_networks n
          where n.store_id = p.store_id
            and n.is_active = true
            and n.public_ip = p.last_login_public_ip
        )
      end
    from public.profiles p
    where p.id = auth.uid()
    limit 1
  ), false)
$$;

drop policy if exists customers_store_select on public.customers;
create policy customers_store_select on public.customers
for select
to authenticated
using (
  is_deleted = false
  and (
    public.current_profile_is_privileged()
    or (
      public.current_profile_has_fresh_network_session()
      and public.current_profile_can_edit_store_records()
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
      public.current_profile_has_fresh_network_session()
      and public.current_profile_can_edit_store_records()
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
      public.current_profile_has_fresh_network_session()
      and public.current_profile_can_edit_store_records()
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
      public.current_profile_has_fresh_network_session()
      and public.current_profile_can_manage_inventory()
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
  plan_change_add_service_delete text,
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
  if not (
    public.current_profile_has_role(array['조회용'])
    and public.current_profile_has_fresh_network_session()
  ) then
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
    c.plan_change_add_service_delete::text,
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

drop policy if exists audit_logs_actor_insert on public.audit_logs;
revoke insert, update, delete on public.audit_logs from anon, authenticated;

revoke update, delete on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;

do $$
begin
  if to_regclass('public.app_updates') is not null then
    alter table public.app_updates
      add column if not exists installer_sha256 text;

    alter table public.app_updates
      drop constraint if exists app_updates_installer_sha256_hex;

    alter table public.app_updates
      add constraint app_updates_installer_sha256_hex
      check (
        installer_sha256 is null
        or installer_sha256 ~* '^[0-9a-f]{64}$'
      );
  end if;
end $$;
