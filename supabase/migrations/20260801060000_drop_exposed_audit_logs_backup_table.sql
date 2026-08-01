-- Security fix: Supabase flagged public.audit_logs_backup_update_profiles_heartbeat_20260716
-- as publicly accessible (RLS disabled, and anon/authenticated had full
-- SELECT/INSERT/UPDATE/DELETE/TRUNCATE grants). It was a one-off manual
-- backup taken before the 20260716050000 migration and is no longer needed
-- now that public.audit_logs is the live, properly RLS-locked table.

drop table if exists public.audit_logs_backup_update_profiles_heartbeat_20260716;
