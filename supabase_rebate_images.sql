-- Rebate image storage and metadata.
-- Run this in the Supabase SQL Editor after supabase_store_access.sql.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'rebate-images',
  'rebate-images',
  false,
  15728640,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.rebate_images (
  id uuid primary key default gen_random_uuid(),
  carrier text not null default 'SKT',
  image_date date not null,
  storage_path text not null unique,
  original_name text not null default '',
  content_type text not null default 'image/jpeg',
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.rebate_images
  add column if not exists carrier text not null default 'SKT';

alter table public.rebate_images
  drop constraint if exists rebate_images_image_date_key;

alter table public.rebate_images
  drop constraint if exists rebate_images_carrier_check;

alter table public.rebate_images
  add constraint rebate_images_carrier_check
  check (carrier in ('SKT', 'KT', 'LG')) not valid;

alter table public.rebate_images
  validate constraint rebate_images_carrier_check;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists rebate_images_set_updated_at on public.rebate_images;
create trigger rebate_images_set_updated_at
before update on public.rebate_images
for each row
execute function public.set_updated_at();

alter table public.rebate_images enable row level security;

grant select on public.rebate_images to authenticated;
grant insert, update, delete on public.rebate_images to authenticated;

drop policy if exists rebate_images_authenticated_select on public.rebate_images;
create policy rebate_images_authenticated_select on public.rebate_images
for select
to authenticated
using (public.current_profile_can_view_rebate());

drop policy if exists rebate_images_privileged_insert on public.rebate_images;
create policy rebate_images_privileged_insert on public.rebate_images
for insert
to authenticated
with check (public.current_profile_is_privileged());

drop policy if exists rebate_images_privileged_update on public.rebate_images;
create policy rebate_images_privileged_update on public.rebate_images
for update
to authenticated
using (public.current_profile_is_privileged())
with check (public.current_profile_is_privileged());

drop policy if exists rebate_images_privileged_delete on public.rebate_images;
create policy rebate_images_privileged_delete on public.rebate_images
for delete
to authenticated
using (public.current_profile_is_privileged());

create index if not exists rebate_images_image_date_idx
  on public.rebate_images(image_date desc);

create unique index if not exists rebate_images_carrier_image_date_unique
  on public.rebate_images(carrier, image_date);

drop policy if exists rebate_storage_authenticated_select on storage.objects;
create policy rebate_storage_authenticated_select on storage.objects
for select
to authenticated
using (
  bucket_id = 'rebate-images'
  and public.current_profile_can_view_rebate()
);

drop policy if exists rebate_storage_privileged_insert on storage.objects;
create policy rebate_storage_privileged_insert on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'rebate-images'
  and public.current_profile_is_privileged()
);

drop policy if exists rebate_storage_privileged_update on storage.objects;
create policy rebate_storage_privileged_update on storage.objects
for update
to authenticated
using (
  bucket_id = 'rebate-images'
  and public.current_profile_is_privileged()
)
with check (
  bucket_id = 'rebate-images'
  and public.current_profile_is_privileged()
);

drop policy if exists rebate_storage_privileged_delete on storage.objects;
create policy rebate_storage_privileged_delete on storage.objects
for delete
to authenticated
using (
  bucket_id = 'rebate-images'
  and public.current_profile_is_privileged()
);

create or replace function public.delete_expired_rebate_images()
returns integer
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  deleted_count integer := 0;
begin
  with expired as (
    delete from public.rebate_images
    where image_date < current_date - interval '93 days'
    returning storage_path
  ),
  deleted_objects as (
    delete from storage.objects
    where bucket_id = 'rebate-images'
      and name in (select storage_path from expired)
    returning id
  )
  select count(*) into deleted_count from expired;

  return deleted_count;
end;
$$;

revoke all on function public.delete_expired_rebate_images() from public, anon, authenticated;

-- Optional daily server-side cleanup. Enable pg_cron in Supabase if this block
-- does not create a job automatically in your project.
create extension if not exists pg_cron with schema extensions;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'delete-expired-rebate-images';

    perform cron.schedule(
      'delete-expired-rebate-images',
      '30 3 * * *',
      'select public.delete_expired_rebate_images();'
    );
  end if;
exception
  when invalid_schema_name or undefined_table or insufficient_privilege then
    raise notice 'pg_cron cleanup job was not installed. Run select public.delete_expired_rebate_images(); from a scheduled Supabase job once per day.';
end;
$$;
