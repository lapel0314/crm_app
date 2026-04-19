-- App auto-update metadata for Pink Phone CRM.
-- Run this in the Supabase SQL Editor, then upload the installer to a public
-- or signed-accessible URL and insert/update the latest row.

create table if not exists public.app_updates (
  id uuid primary key default gen_random_uuid(),
  platform text not null default 'windows',
  version text not null,
  installer_url text not null,
  latest_version text,
  min_required_version text,
  apk_url text,
  update_message text,
  notes text,
  auto_install boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.app_updates add column if not exists latest_version text;
alter table public.app_updates add column if not exists min_required_version text;
alter table public.app_updates add column if not exists apk_url text;
alter table public.app_updates add column if not exists update_message text;

create index if not exists app_updates_platform_active_created_idx
  on public.app_updates(platform, is_active, created_at desc);

alter table public.app_updates enable row level security;

drop policy if exists app_updates_public_select on public.app_updates;
create policy app_updates_public_select on public.app_updates
for select
to authenticated, anon
using (is_active = true);

-- Example for the next release:
-- update public.app_updates
-- set is_active = false
-- where platform = 'windows' and is_active = true;
--
-- insert into public.app_updates (platform, version, installer_url, notes)
-- values (
--   'windows',
--   '1.0.3',
--   'https://your-project.supabase.co/storage/v1/object/public/installers/핑크폰%20설치%201.0.3.exe',
--   '업데이트 내용'
-- );
--
-- Android manual APK forced update example:
-- update public.app_updates
-- set is_active = false
-- where platform = 'android' and is_active = true;
--
-- insert into public.app_updates (
--   platform,
--   version,
--   installer_url,
--   latest_version,
--   min_required_version,
--   apk_url,
--   update_message
-- )
-- values (
--   'android',
--   '1.0.4',
--   'https://your-project.supabase.co/storage/v1/object/public/installers/pinkphone-crm-1.0.4.apk',
--   '1.0.4',
--   '1.0.4',
--   'https://your-project.supabase.co/storage/v1/object/public/installers/pinkphone-crm-1.0.4.apk',
--   '새 Android 앱을 설치한 뒤 다시 실행해주세요.'
-- );
