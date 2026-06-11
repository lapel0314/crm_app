alter table public.customers
  add column if not exists plan_change_add_service_delete text;

drop function if exists public.customer_open_rows();

create function public.customer_open_rows()
returns table (
  id text,
  join_date text,
  created_at text,
  m3 text,
  m6 text,
  staff text,
  name text,
  phone text,
  join_type text,
  carrier text,
  previous_carrier text,
  model text,
  plan text,
  add_service text,
  contract_type text,
  installment text,
  rebate text,
  add_rebate text,
  hidden_rebate text,
  hidden_note text,
  deduction text,
  deduction_note text,
  support_money text,
  payment text,
  payment_note text,
  deposit text,
  bank_info text,
  trade_in boolean,
  trade_model text,
  trade_price text,
  total_rebate text,
  tax text,
  margin text,
  memo text,
  plan_change_add_service_delete text,
  store text,
  mobile text,
  second text,
  kakao_chat_type text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.current_profile_has_role(array['조회용']) then
    return;
  end if;

  return query
  select
    c.id::text,
    c.join_date::text,
    c.created_at::text,
    c.m3::text,
    c.m6::text,
    c.staff::text,
    public.mask_name(c.name::text),
    public.mask_phone(c.phone::text),
    c.join_type::text,
    c.carrier::text,
    c.previous_carrier::text,
    c.model::text,
    c.plan::text,
    c.add_service::text,
    c.contract_type::text,
    c.installment::text,
    c.rebate::text,
    c.add_rebate::text,
    c.hidden_rebate::text,
    c.hidden_note::text,
    c.deduction::text,
    c.deduction_note::text,
    c.support_money::text,
    c.payment::text,
    c.payment_note::text,
    c.deposit::text,
    public.mask_bank_info(c.bank_info::text),
    c.trade_in,
    c.trade_model::text,
    c.trade_price::text,
    c.total_rebate::text,
    c.tax::text,
    c.margin::text,
    c.memo::text,
    c.plan_change_add_service_delete::text,
    c.store::text,
    c.mobile::text,
    c.second::text,
    c.kakao_chat_type::text
  from public.customers c
  where c.is_deleted = false
    and c.normalized_store = public.current_profile_store()
  order by c.join_date asc nulls last, c.created_at asc nulls last;
end;
$$;

grant execute on function public.customer_open_rows() to authenticated;
