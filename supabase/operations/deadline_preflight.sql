-- Read-only. Save results before applying any deadline migration.
select table_schema, table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and (column_name = 'manual_due_date'
       or (table_name in ('items', 'deleted_items') and column_name in ('id', 'created_at')))
order by table_name, column_name;

select 'items' as table_name, count(*) as rows,
       count(*) filter (where manual_due_date is null) as null_deadlines,
       count(*) filter (where created_at is null) as null_created_at
from public.items
union all
select 'deleted_items', count(*),
       count(*) filter (where manual_due_date is null),
       count(*) filter (where created_at is null)
from public.deleted_items;

select tgrelid::regclass as table_name, tgname, pg_get_triggerdef(oid)
from pg_trigger
where tgrelid in ('public.items'::regclass, 'public.deleted_items'::regclass)
  and not tgisinternal;

-- Export these results to compare explicit deadlines after migration.
select 'items' as table_name, id, manual_due_date
from public.items where manual_due_date is not null
union all
select 'deleted_items', id, manual_due_date
from public.deleted_items where manual_due_date is not null;

-- These rows block backfill. Recover their original creation timestamp or assign
-- an explicitly reviewed deadline before migration; do not substitute now().
select id, title, created_at, manual_due_date
from public.deleted_items
where created_at is null and manual_due_date is null;
