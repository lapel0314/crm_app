create or replace function public.set_customer_settlement_months()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  parsed_join_date timestamp;
begin
  if new.join_date is null or btrim(new.join_date::text) = '' then
    new.m3 := null;
    new.m6 := null;
    return new;
  end if;

  if new.join_date::text !~ '^\d{4}-\d{2}-\d{2}' then
    return new;
  end if;

  parsed_join_date := new.join_date::timestamp;
  new.m3 := to_char(
    date_trunc('month', parsed_join_date) + interval '4 months',
    'YYYY-MM'
  );
  new.m6 := to_char(
    date_trunc('month', parsed_join_date) + interval '7 months',
    'YYYY-MM'
  );
  return new;
exception
  when others then
    return new;
end;
$$;

drop trigger if exists set_customer_settlement_months on public.customers;

create trigger set_customer_settlement_months
before insert or update of join_date, m3, m6 on public.customers
for each row
execute function public.set_customer_settlement_months();

with recalculated as (
  select
    id,
    to_char(
      date_trunc('month', join_date::timestamp) + interval '4 months',
      'YYYY-MM'
    ) as expected_m3,
    to_char(
      date_trunc('month', join_date::timestamp) + interval '7 months',
      'YYYY-MM'
    ) as expected_m6
  from public.customers
  where join_date is not null
    and btrim(join_date::text) <> ''
    and join_date::text ~ '^\d{4}-\d{2}-\d{2}'
)
update public.customers as c
set
  m3 = r.expected_m3,
  m6 = r.expected_m6
from recalculated as r
where c.id = r.id
  and (
    c.m3 is distinct from r.expected_m3
    or c.m6 is distinct from r.expected_m6
  );
