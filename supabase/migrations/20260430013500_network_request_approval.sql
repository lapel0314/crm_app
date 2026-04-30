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

drop trigger if exists store_network_requests_set_updated_at on public.store_network_requests;
create trigger store_network_requests_set_updated_at
before update on public.store_network_requests
for each row execute function public.set_updated_at();

alter table public.store_network_requests enable row level security;

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
