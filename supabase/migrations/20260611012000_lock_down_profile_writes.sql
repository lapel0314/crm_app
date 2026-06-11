-- Profile writes must go through trusted triggers or the auth-policy Edge Function.

drop policy if exists profiles_insert_self on public.profiles;
drop policy if exists profiles_update_self_or_admin on public.profiles;
drop policy if exists "profiles delete by admin" on public.profiles;
drop policy if exists profiles_privileged_update on public.profiles;
drop policy if exists profiles_privileged_delete on public.profiles;

revoke insert, update, delete on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
