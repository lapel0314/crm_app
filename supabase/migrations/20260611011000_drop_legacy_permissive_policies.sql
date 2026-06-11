-- Remove older permissive RLS policies that can OR-bypass the hardened store policies.

drop policy if exists customers_select_by_role on public.customers;
drop policy if exists customers_insert_by_role on public.customers;
drop policy if exists customers_update_by_role on public.customers;
drop policy if exists customers_delete_by_role on public.customers;

drop policy if exists leads_select_by_role on public.leads;
drop policy if exists leads_insert_by_role on public.leads;
drop policy if exists leads_update_by_role on public.leads;
drop policy if exists leads_delete_by_role on public.leads;

drop policy if exists wired_members_select_by_role on public.wired_members;
drop policy if exists wired_members_insert_by_role on public.wired_members;
drop policy if exists wired_members_update_by_role on public.wired_members;
drop policy if exists wired_members_delete_by_role on public.wired_members;

drop policy if exists device_inventory_select_staff_up on public.device_inventory;
drop policy if exists device_inventory_insert_staff_up on public.device_inventory;
drop policy if exists device_inventory_update_staff_up on public.device_inventory;
drop policy if exists device_inventory_delete_manager_up on public.device_inventory;

drop policy if exists audit_logs_insert_staff_up on public.audit_logs;
