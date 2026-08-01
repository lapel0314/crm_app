-- Client request: capture customer date of birth for both 고객DB and 유선회원.
-- Nullable — existing rows have no birth date and it's optional on new entries.
-- Not exposed through customer_open_rows() (조회용 masked view) by design.
--
-- text, not date: 카카오톡 등록/수정 자동화가 "700725" 같은 6자리 YYMMDD를
-- 그대로 보내온다. date 타입이면 세기 추론 변환이 강제되고, 변환 실패 시
-- 등록/수정 자체가 서버 오류로 실패한다. 입력값을 그대로 저장한다.

alter table public.customers
  add column if not exists birth_date text;

alter table public.wired_members
  add column if not exists birth_date text;
