-- Apply before deploying the new app. Compatible with older null-sending clients.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

create function public.automatic_pickup_deadline(created_at timestamptz)
returns date
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select (date_trunc('month', ((created_at at time zone 'America/Los_Angeles')::date + 14)::timestamp)
          + interval '1 month' - interval '1 day')::date;
$$;

create function public.fill_pickup_deadline()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.manual_due_date is null then
    if new.created_at is null then
      raise exception 'A creation timestamp is required to calculate the pickup deadline'
        using errcode = '23502';
    end if;
    new.manual_due_date := public.automatic_pickup_deadline(new.created_at);
  end if;
  return new;
end;
$$;

create trigger fill_pickup_deadline
before insert or update on public.items
for each row execute function public.fill_pickup_deadline();

create trigger fill_pickup_deadline
before insert or update on public.deleted_items
for each row execute function public.fill_pickup_deadline();

-- NOT VALID avoids scanning old rows while holding the schema-change lock.
alter table public.items add constraint items_deadline_present
  check (manual_due_date is not null) not valid;
alter table public.deleted_items add constraint deleted_items_deadline_present
  check (manual_due_date is not null) not valid;
commit;
