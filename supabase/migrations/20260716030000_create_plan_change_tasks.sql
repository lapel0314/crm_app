create table if not exists public.plan_change_tasks (
  id uuid primary key default gen_random_uuid(),
  customer_id text not null,
  customer_name text,
  phone text,
  store text,
  normalized_store text not null default '',
  carrier_group text not null check (carrier_group in ('SK', 'KT', 'LG', '알뜰폰')),
  task_type text not null check (
    task_type in (
      'add_service_delete',
      'selective_plan_change',
      'public_subsidy',
      'selective_with_support'
    )
  ),
  due_date date not null,
  status text not null default 'pending' check (status in ('pending', 'done', 'skipped')),
  before_value text,
  after_value text,
  action_detail text,
  note text,
  completed_at timestamptz,
  completed_by uuid references public.profiles(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint plan_change_tasks_customer_type_due_key unique (customer_id, task_type, due_date)
);

create index if not exists plan_change_tasks_customer_idx
  on public.plan_change_tasks(customer_id, due_date desc);

create index if not exists plan_change_tasks_status_idx
  on public.plan_change_tasks(status, due_date, normalized_store);

drop trigger if exists plan_change_tasks_set_updated_at on public.plan_change_tasks;
create trigger plan_change_tasks_set_updated_at
before update on public.plan_change_tasks
for each row execute function public.set_updated_at();

create table if not exists public.plan_change_task_logs (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.plan_change_tasks(id) on delete cascade,
  action text not null check (action in ('created', 'completed', 'skipped', 'reopened', 'updated')),
  before_value text,
  after_value text,
  note text,
  actor_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists plan_change_task_logs_task_idx
  on public.plan_change_task_logs(task_id, created_at desc);

alter table public.plan_change_tasks enable row level security;
alter table public.plan_change_task_logs enable row level security;

drop policy if exists plan_change_tasks_store_select on public.plan_change_tasks;
create policy plan_change_tasks_store_select on public.plan_change_tasks
for select
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_has_fresh_network_session()
    and public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists plan_change_tasks_store_insert on public.plan_change_tasks;
create policy plan_change_tasks_store_insert on public.plan_change_tasks
for insert
to authenticated
with check (
  public.current_profile_is_privileged()
  or (
    public.current_profile_has_fresh_network_session()
    and public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists plan_change_tasks_store_update on public.plan_change_tasks;
create policy plan_change_tasks_store_update on public.plan_change_tasks
for update
to authenticated
using (
  public.current_profile_is_privileged()
  or (
    public.current_profile_has_fresh_network_session()
    and public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
)
with check (
  public.current_profile_is_privileged()
  or (
    public.current_profile_has_fresh_network_session()
    and public.current_profile_can_edit_store_records()
    and normalized_store = public.current_profile_store()
  )
);

drop policy if exists plan_change_task_logs_store_select on public.plan_change_task_logs;
create policy plan_change_task_logs_store_select on public.plan_change_task_logs
for select
to authenticated
using (
  exists (
    select 1
    from public.plan_change_tasks task
    where task.id = task_id
      and (
        public.current_profile_is_privileged()
        or (
          public.current_profile_has_fresh_network_session()
          and public.current_profile_can_edit_store_records()
          and task.normalized_store = public.current_profile_store()
        )
      )
  )
);

drop policy if exists plan_change_task_logs_store_insert on public.plan_change_task_logs;
create policy plan_change_task_logs_store_insert on public.plan_change_task_logs
for insert
to authenticated
with check (
  actor_id = auth.uid()
  and exists (
    select 1
    from public.plan_change_tasks task
    where task.id = task_id
      and (
        public.current_profile_is_privileged()
        or (
          public.current_profile_has_fresh_network_session()
          and public.current_profile_can_edit_store_records()
          and task.normalized_store = public.current_profile_store()
        )
      )
  )
);
