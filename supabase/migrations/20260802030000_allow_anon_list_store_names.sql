-- 회원가입 화면(로그인 전)에서 매장명 드롭다운을 채우기 위해
-- 활성 매장 "이름만" 반환하는 함수를 anon에 개방한다.
-- stores 테이블 자체의 RLS(authenticated + 매장 스코프)는 그대로 유지.
create or replace function public.list_active_store_names()
returns setof text
language sql
stable
security definer
set search_path = public
as $$
  select name
  from public.stores
  where is_active = true
  order by name;
$$;

revoke all on function public.list_active_store_names() from public;
grant execute on function public.list_active_store_names()
  to anon, authenticated;
