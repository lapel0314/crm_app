create table if not exists public.model_name_mappings (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,
  registered_names text[] not null default '{}',
  is_active boolean not null default true,
  memo text,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint model_name_mappings_display_name_not_blank
    check (length(trim(display_name)) > 0)
);

create index if not exists model_name_mappings_display_name_idx
  on public.model_name_mappings(display_name);

drop trigger if exists model_name_mappings_set_updated_at
  on public.model_name_mappings;
create trigger model_name_mappings_set_updated_at
before update on public.model_name_mappings
for each row execute function public.set_updated_at();

alter table public.model_name_mappings enable row level security;

drop policy if exists model_name_mappings_select on public.model_name_mappings;
create policy model_name_mappings_select on public.model_name_mappings
for select
to authenticated
using (
  is_active
  or public.current_profile_is_privileged()
);

drop policy if exists model_name_mappings_insert on public.model_name_mappings;
create policy model_name_mappings_insert on public.model_name_mappings
for insert
to authenticated
with check (
  public.current_profile_is_privileged()
);

drop policy if exists model_name_mappings_update on public.model_name_mappings;
create policy model_name_mappings_update on public.model_name_mappings
for update
to authenticated
using (
  public.current_profile_is_privileged()
)
with check (
  public.current_profile_is_privileged()
);

drop policy if exists model_name_mappings_delete on public.model_name_mappings;
create policy model_name_mappings_delete on public.model_name_mappings
for delete
to authenticated
using (
  public.current_profile_is_privileged()
);

drop trigger if exists audit_model_name_mappings_changes
  on public.model_name_mappings;
create trigger audit_model_name_mappings_changes
after insert or update or delete on public.model_name_mappings
for each row execute function public.audit_crm_row_change();
