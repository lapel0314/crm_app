-- Rebate rate card rules.
-- Run after supabase_store_access.sql.

create table if not exists public.rebate_rate_cards (
  id uuid primary key default gen_random_uuid(),
  carrier text not null default '',
  model_name text not null,
  model_key text not null,
  plan_name text not null,
  plan_key text not null,
  join_type text not null default '',
  contract_type text not null default '',
  add_service_name text not null default '',
  add_service_key text not null default '',
  base_rebate integer not null default 0,
  add_rebate integer not null default 0,
  deduction integer not null default 0,
  memo text not null default '',
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rebate_rate_cards_amount_check
    check (base_rebate >= 0 and add_rebate >= 0 and deduction >= 0),
  constraint rebate_rate_cards_carrier_check
    check (carrier in ('', 'SKT', 'KT', 'LG')),
  constraint rebate_rate_cards_join_type_check
    check (join_type in ('', '신규', '번호이동', '기변')),
  constraint rebate_rate_cards_contract_type_check
    check (contract_type in ('', '공시', '선약'))
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create unique index if not exists rebate_rate_cards_unique_rule_idx
  on public.rebate_rate_cards(
    carrier,
    model_key,
    plan_key,
    join_type,
    contract_type,
    add_service_key
  );

create index if not exists rebate_rate_cards_lookup_idx
  on public.rebate_rate_cards(is_active, model_key, plan_key);

create table if not exists public.rebate_rate_card_sources (
  carrier text primary key,
  csv_url text not null,
  last_synced_at timestamptz,
  last_sync_error text not null default '',
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rebate_rate_card_sources_carrier_check
    check (carrier in ('SKT', 'KT', 'LG')),
  constraint rebate_rate_card_sources_google_csv_check
    check (
      csv_url like 'https://docs.google.com/spreadsheets/%'
      and (csv_url like '%output=csv%' or csv_url like '%format=csv%')
    )
);

drop trigger if exists rebate_rate_card_sources_set_updated_at on public.rebate_rate_card_sources;
create trigger rebate_rate_card_sources_set_updated_at
before update on public.rebate_rate_card_sources
for each row
execute function public.set_updated_at();

drop trigger if exists rebate_rate_cards_set_updated_at on public.rebate_rate_cards;
create trigger rebate_rate_cards_set_updated_at
before update on public.rebate_rate_cards
for each row
execute function public.set_updated_at();

alter table public.rebate_rate_cards enable row level security;
alter table public.rebate_rate_card_sources enable row level security;

grant select on public.rebate_rate_cards to authenticated;
grant insert, update, delete on public.rebate_rate_cards to authenticated;
grant select, insert, update, delete on public.rebate_rate_card_sources to authenticated;

drop policy if exists rebate_rate_cards_approved_select on public.rebate_rate_cards;
create policy rebate_rate_cards_approved_select on public.rebate_rate_cards
for select
to authenticated
using (
  public.current_profile_has_role(array['대표', '개발자', '점장', '사원', '조회용'])
);

drop policy if exists rebate_rate_cards_privileged_insert on public.rebate_rate_cards;
create policy rebate_rate_cards_privileged_insert on public.rebate_rate_cards
for insert
to authenticated
with check (public.current_profile_is_privileged());

drop policy if exists rebate_rate_cards_privileged_update on public.rebate_rate_cards;
create policy rebate_rate_cards_privileged_update on public.rebate_rate_cards
for update
to authenticated
using (public.current_profile_is_privileged())
with check (public.current_profile_is_privileged());

drop policy if exists rebate_rate_cards_privileged_delete on public.rebate_rate_cards;
create policy rebate_rate_cards_privileged_delete on public.rebate_rate_cards
for delete
to authenticated
using (public.current_profile_is_privileged());

drop policy if exists rebate_rate_card_sources_privileged_select on public.rebate_rate_card_sources;
create policy rebate_rate_card_sources_privileged_select on public.rebate_rate_card_sources
for select
to authenticated
using (public.current_profile_is_privileged());

drop policy if exists rebate_rate_card_sources_privileged_insert on public.rebate_rate_card_sources;
create policy rebate_rate_card_sources_privileged_insert on public.rebate_rate_card_sources
for insert
to authenticated
with check (public.current_profile_is_privileged());

drop policy if exists rebate_rate_card_sources_privileged_update on public.rebate_rate_card_sources;
create policy rebate_rate_card_sources_privileged_update on public.rebate_rate_card_sources
for update
to authenticated
using (public.current_profile_is_privileged())
with check (public.current_profile_is_privileged());

drop policy if exists rebate_rate_card_sources_privileged_delete on public.rebate_rate_card_sources;
create policy rebate_rate_card_sources_privileged_delete on public.rebate_rate_card_sources
for delete
to authenticated
using (public.current_profile_is_privileged());
