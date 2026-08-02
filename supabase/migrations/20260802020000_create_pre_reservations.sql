-- 사전예약 고객 관리 테이블 (가망고객 페이지에서 진입하는 별도 화면용).
create table if not exists public.pre_reservations (
  id uuid primary key default gen_random_uuid(),
  customer_name text not null default '',
  phone text not null default '',
  carrier text not null default '',
  -- 공시/선약
  subsidy_type text not null default '',
  reserved_model text not null default '',
  reserved_color text not null default '',
  reservation_number text not null default '',
  receive_date date,
  id_scanned boolean not null default false,
  status text not null default '대기'
    check (status in ('대기', '완료', '취소')),
  store text not null default '',
  normalized_store text generated always as
    (public.normalize_store_name(store)) stored,
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  deleted_by uuid,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists pre_reservations_store_idx
  on public.pre_reservations(normalized_store);
create index if not exists pre_reservations_receive_date_idx
  on public.pre_reservations(receive_date);
create index if not exists pre_reservations_status_idx
  on public.pre_reservations(status);

drop trigger if exists pre_reservations_set_updated_at
  on public.pre_reservations;
create trigger pre_reservations_set_updated_at
before update on public.pre_reservations
for each row execute function public.set_updated_at();

alter table public.pre_reservations enable row level security;

drop policy if exists pre_reservations_store_select on public.pre_reservations;
create policy pre_reservations_store_select on public.pre_reservations
for select
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_has_fresh_network_session()
    and public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists pre_reservations_store_insert on public.pre_reservations;
create policy pre_reservations_store_insert on public.pre_reservations
for insert
to authenticated
with check (
  public.current_profile_is_privileged()
  or (
    public.current_profile_has_fresh_network_session()
    and public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists pre_reservations_store_update on public.pre_reservations;
create policy pre_reservations_store_update on public.pre_reservations
for update
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_has_fresh_network_session()
    and public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
)
with check (
  public.current_profile_is_privileged()
  or (
    public.current_profile_has_fresh_network_session()
    and public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists pre_reservations_store_delete on public.pre_reservations;
create policy pre_reservations_store_delete on public.pre_reservations
for delete
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_has_fresh_network_session()
    and public.current_profile_can_delete_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop trigger if exists audit_pre_reservations_changes
  on public.pre_reservations;
create trigger audit_pre_reservations_changes
after insert or update or delete on public.pre_reservations
for each row execute function public.audit_crm_row_change();
