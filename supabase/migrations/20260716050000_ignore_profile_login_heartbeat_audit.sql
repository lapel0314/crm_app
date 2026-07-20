-- Skip noisy profile audit rows produced by periodic login-policy heartbeats.
-- Real profile changes such as role, approval, store, name, and phone remain audited.

create or replace function public.audit_crm_row_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and tg_table_name = 'profiles' then
    if not exists (
      select 1
      from (
        select key from jsonb_object_keys(to_jsonb(old)) as key
        union
        select key from jsonb_object_keys(to_jsonb(new)) as key
      ) keys
      where (to_jsonb(old)->key) is distinct from (to_jsonb(new)->key)
        and key not in (
          'last_login_at',
          'last_login_platform',
          'last_login_public_ip',
          'login_policy_message'
        )
    ) then
      return new;
    end if;
  end if;

  insert into public.audit_logs(actor_id, action, target_table, target_id, detail)
  values (
    auth.uid(),
    lower(tg_op) || '_' || tg_table_name,
    tg_table_name,
    coalesce(new.id::text, old.id::text),
    jsonb_build_object(
      'old', case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
      'new', case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
    )
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
