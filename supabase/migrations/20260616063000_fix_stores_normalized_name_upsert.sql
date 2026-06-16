-- Make stores upsert compatible with onConflict: 'normalized_name'.
-- The previous partial unique index could not satisfy ON CONFLICT(normalized_name).

update public.stores
set normalized_name = 'store_' || id::text
where normalized_name = '';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.stores'::regclass
      and conname = 'stores_normalized_name_unique'
  ) then
    alter table public.stores
      add constraint stores_normalized_name_unique unique (normalized_name);
  end if;
end $$;
