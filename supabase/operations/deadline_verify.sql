-- Re-run deadline_preflight.sql too: counts and original explicit dates must match
-- (account for legitimate writes made by users during rollout).
select table_name, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name in ('items', 'deleted_items')
  and column_name = 'manual_due_date';

select 'items' as table_name, count(*) as null_deadlines
from public.items where manual_due_date is null
union all
select 'deleted_items', count(*)
from public.deleted_items where manual_due_date is null;

select id, manual_due_date, created_at from public.items
order by manual_due_date, created_at, id limit 50;
