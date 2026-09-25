-- Validated checks allow SET NOT NULL without another table scan.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';
alter table public.items alter column manual_due_date set not null;
alter table public.deleted_items alter column manual_due_date set not null;
alter table public.items drop constraint items_deadline_present;
alter table public.deleted_items drop constraint deleted_items_deadline_present;
commit;
