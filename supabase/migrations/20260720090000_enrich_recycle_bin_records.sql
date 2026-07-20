-- Enrich recycle-bin rows with human-readable delete actor and common detail fields.

drop function if exists public.crm_deleted_records();

create or replace function public.crm_deleted_records()
returns table (
  target_table text,
  target_id text,
  store text,
  title text,
  subtitle text,
  deleted_at timestamptz,
  deleted_by uuid,
  deleted_by_name text,
  join_date text,
  model text
)
language sql
stable
security definer
set search_path = public
as $$
  select * from (
    select
      'customers'::text,
      c.id::text,
      c.store::text,
      coalesce(c.name::text, '-') as title,
      coalesce(c.phone::text, '') as subtitle,
      c.deleted_at,
      c.deleted_by,
      coalesce(p.name::text, p.email::text, '') as deleted_by_name,
      c.join_date::text,
      c.model::text
    from public.customers c
    left join public.profiles p on p.id = c.deleted_by
    where c.is_deleted = true

    union all

    select
      'leads'::text,
      l.id::text,
      l.store::text,
      coalesce(l.subscriber::text, '-') as title,
      coalesce(l.phone::text, '') as subtitle,
      l.deleted_at,
      l.deleted_by,
      coalesce(p.name::text, p.email::text, '') as deleted_by_name,
      ''::text as join_date,
      ''::text as model
    from public.leads l
    left join public.profiles p on p.id = l.deleted_by
    where l.is_deleted = true

    union all

    select
      'wired_members'::text,
      w.id::text,
      w.store::text,
      coalesce(w.subscriber::text, '-') as title,
      coalesce(w.phone::text, '') as subtitle,
      w.deleted_at,
      w.deleted_by,
      coalesce(p.name::text, p.email::text, '') as deleted_by_name,
      ''::text as join_date,
      ''::text as model
    from public.wired_members w
    left join public.profiles p on p.id = w.deleted_by
    where w.is_deleted = true

    union all

    select
      'device_inventory'::text,
      d.id::text,
      d.store::text,
      coalesce(d.model_name::text, '-') as title,
      coalesce(d.serial_number::text, '') as subtitle,
      d.deleted_at,
      d.deleted_by,
      coalesce(p.name::text, p.email::text, '') as deleted_by_name,
      ''::text as join_date,
      d.model_name::text as model
    from public.device_inventory d
    left join public.profiles p on p.id = d.deleted_by
    where d.is_deleted = true
  ) rows
  where public.current_profile_is_privileged()
  order by deleted_at desc nulls last
  limit 200
$$;

grant execute on function public.crm_deleted_records() to authenticated;
