-- App auto-update metadata for Pink Phone CRM.
-- Run this in the Supabase SQL Editor, then upload the installer to a public
-- or signed-accessible URL and insert/update the latest row.

create table if not exists public.app_updates (
  id uuid primary key default gen_random_uuid(),
  platform text not null default 'windows',
  version text not null,
  installer_url text not null,
  notes text,
  auto_install boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists app_updates_platform_active_created_idx
  on public.app_updates(platform, is_active, created_at desc);

alter table public.app_updates enable row level security;

drop policy if exists app_updates_public_select on public.app_updates;
create policy app_updates_public_select on public.app_updates
for select
to authenticated, anon
using (is_active = true);

-- Example for the next release:
-- insert into public.app_updates (platform, version, installer_url, notes)
-- values (
--   'windows',
--   '1.0.1',
--   'https://ysafjyubntkeorriywmu.supabase.co/storage/v1/object/public/installers/%ED%95%91%ED%81%AC%ED%8F%B0%20%EC%84%A4%EC%B9%98.exe',
--   '업데이트 내용'
-- );
