-- 고객정리(데이터 점검)에서 확인 완료/예외 처리한 이슈를 저장한다.
-- issue_key에 검사 대상 값의 지문(fingerprint)을 포함해,
-- 값이 수정되면 키가 달라져 자동으로 다시 검출된다.
create table if not exists public.data_quality_dismissals (
  id uuid primary key default gen_random_uuid(),
  issue_type text not null,
  issue_key text not null,
  customer_id text,
  customer_name text not null default '',
  customer_phone text not null default '',
  customer_store text not null default '',
  member_count int,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint data_quality_dismissals_type_key_unique
    unique (issue_type, issue_key),
  constraint data_quality_dismissals_issue_type_check
    check (issue_type in ('phone', 'join_date', 'carrier', 'duplicate'))
);

create index if not exists data_quality_dismissals_customer_idx
  on public.data_quality_dismissals(customer_id);

drop trigger if exists data_quality_dismissals_set_updated_at
  on public.data_quality_dismissals;
create trigger data_quality_dismissals_set_updated_at
before update on public.data_quality_dismissals
for each row execute function public.set_updated_at();

alter table public.data_quality_dismissals enable row level security;

drop policy if exists data_quality_dismissals_select
  on public.data_quality_dismissals;
create policy data_quality_dismissals_select on public.data_quality_dismissals
for select
to authenticated
using (
  public.current_profile_is_privileged()
);

drop policy if exists data_quality_dismissals_insert
  on public.data_quality_dismissals;
create policy data_quality_dismissals_insert on public.data_quality_dismissals
for insert
to authenticated
with check (
  public.current_profile_is_privileged()
);

drop policy if exists data_quality_dismissals_update
  on public.data_quality_dismissals;
create policy data_quality_dismissals_update on public.data_quality_dismissals
for update
to authenticated
using (
  public.current_profile_is_privileged()
)
with check (
  public.current_profile_is_privileged()
);

drop policy if exists data_quality_dismissals_delete
  on public.data_quality_dismissals;
create policy data_quality_dismissals_delete on public.data_quality_dismissals
for delete
to authenticated
using (
  public.current_profile_is_privileged()
);

drop trigger if exists audit_data_quality_dismissals_changes
  on public.data_quality_dismissals;
create trigger audit_data_quality_dismissals_changes
after insert or update or delete on public.data_quality_dismissals
for each row execute function public.audit_crm_row_change();
