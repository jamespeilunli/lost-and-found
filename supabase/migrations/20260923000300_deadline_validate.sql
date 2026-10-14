begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';
alter table public.items validate constraint items_deadline_present;
alter table public.deleted_items validate constraint deleted_items_deadline_present;
commit;
