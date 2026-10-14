-- Null-only updates preserve every explicit deadline.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';
update public.items
set manual_due_date = public.automatic_pickup_deadline(created_at)
where manual_due_date is null;
update public.deleted_items
set manual_due_date = public.automatic_pickup_deadline(created_at)
where manual_due_date is null;
commit;
