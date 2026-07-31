-- current_profile_has_role() previously fell back to the unvalidated raw
-- `role` text (coalesce(role_code::text, role)) whenever role_code was null.
-- This is the same class of bug fixed in auth-policy's Edge Function
-- (roleCode() vs roleText()): a profile whose role_code is null but whose
-- free-text `role` column happens to say 대표/개발자 must never be treated
-- as privileged. This function underlies current_profile_is_privileged(),
-- current_profile_is_manager(), and most RLS policies across the app, so
-- fixing it here closes the gap everywhere at once.

create or replace function public.current_profile_has_role(allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and approval_status = 'approved'
      and role_code::text = any(allowed_roles)
  )
$$;
