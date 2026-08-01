-- Private storage for Windows/Android installer binaries, replacing public
-- GitHub Release links. Follows the same pattern as supabase_rebate_images.sql
-- (private bucket + storage.objects RLS + client-side createSignedUrl()).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'app-installers',
  'app-installers',
  false,
  314572800,
  array[
    'application/octet-stream',
    'application/x-msdownload',
    'application/vnd.android.package-archive'
  ]
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Nullable: when set, the client resolves a signed download URL from this
-- bucket instead of using installer_url/apk_url directly. Existing active
-- rows keep working via the legacy public-URL columns until republished.
alter table public.app_updates add column if not exists storage_path text;

-- Any authenticated account (approved or not) may read/sign objects in this
-- bucket: an employee needs the latest app before they can be evaluated by
-- login policy at all, so gating on approval_status would be a deadlock.
-- Publishing a new installer stays privileged-only.
drop policy if exists app_installers_authenticated_select on storage.objects;
create policy app_installers_authenticated_select on storage.objects
for select
to authenticated
using (bucket_id = 'app-installers');

drop policy if exists app_installers_privileged_insert on storage.objects;
create policy app_installers_privileged_insert on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'app-installers'
  and public.current_profile_is_privileged()
);

drop policy if exists app_installers_privileged_update on storage.objects;
create policy app_installers_privileged_update on storage.objects
for update
to authenticated
using (
  bucket_id = 'app-installers'
  and public.current_profile_is_privileged()
)
with check (
  bucket_id = 'app-installers'
  and public.current_profile_is_privileged()
);

drop policy if exists app_installers_privileged_delete on storage.objects;
create policy app_installers_privileged_delete on storage.objects
for delete
to authenticated
using (
  bucket_id = 'app-installers'
  and public.current_profile_is_privileged()
);
