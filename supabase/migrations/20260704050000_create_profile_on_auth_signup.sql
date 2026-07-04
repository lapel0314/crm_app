create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  role_text text := coalesce(new.raw_user_meta_data ->> 'role', '');
  store_text text := public.normalize_store_name(
    coalesce(new.raw_user_meta_data ->> 'store', '')
  );
  target_store_id uuid;
begin
  if store_text <> '' then
    select id
      into target_store_id
      from public.stores
     where normalized_name = store_text
       and is_active = true
     limit 1;
  end if;

  insert into public.profiles (
    id,
    email,
    name,
    phone,
    role,
    role_code,
    store,
    store_id,
    approval_status
  )
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'name', ''),
    coalesce(new.raw_user_meta_data ->> 'phone', ''),
    role_text,
    case
      when role_text in ('대표', '개발자', '점장', '사원', '조회용')
        then role_text::public.app_role
      else null
    end,
    store_text,
    target_store_id,
    'pending'
  )
  on conflict (id) do update set
    email = excluded.email,
    name = excluded.name,
    phone = excluded.phone,
    role = excluded.role,
    role_code = coalesce(excluded.role_code, public.profiles.role_code),
    store = excluded.store,
    store_id = coalesce(excluded.store_id, public.profiles.store_id),
    approval_status = coalesce(public.profiles.approval_status, 'pending');

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();
