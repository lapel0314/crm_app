-- KakaoTalk PC send logs and optional customer Kakao fields.
-- Run in the Supabase SQL Editor before using the CRM Kakao send feature.

alter table public.customers
  add column if not exists kakao_chat_type text default 'friend'
    check (kakao_chat_type in ('friend', 'group', 'openChat')),
  add column if not exists kakao_room_name text,
  add column if not exists kakao_search_name text;

create table if not exists public.kakao_send_logs (
  id uuid primary key default gen_random_uuid(),
  target_name text not null,
  message text not null,
  success boolean not null default false,
  error_message text,
  sent_at timestamptz not null default now(),
  sent_by uuid references auth.users(id)
);

create index if not exists kakao_send_logs_sent_at_idx
  on public.kakao_send_logs(sent_at desc);

create index if not exists kakao_send_logs_sent_by_idx
  on public.kakao_send_logs(sent_by);

alter table public.kakao_send_logs enable row level security;

drop policy if exists kakao_send_logs_insert on public.kakao_send_logs;
create policy kakao_send_logs_insert on public.kakao_send_logs
for insert
to authenticated
with check (sent_by = auth.uid());

drop policy if exists kakao_send_logs_select_own on public.kakao_send_logs;
create policy kakao_send_logs_select_own on public.kakao_send_logs
for select
to authenticated
using (sent_by = auth.uid());
