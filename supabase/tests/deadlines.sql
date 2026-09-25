-- Run only in an EMPTY disposable database:
-- psql -v ON_ERROR_STOP=1 -f supabase/tests/deadlines.sql <connection>
create table public.items (
  id integer primary key, created_at timestamptz not null default now(),
  manual_due_date date, title text
);
create table public.deleted_items (
  id integer primary key, created_at timestamptz null,
  manual_due_date date, title text
);
insert into public.items values
  (1, '2026-01-18 20:00Z', null, 'automatic'),
  (2, '2026-01-18 20:00Z', '2026-04-01', 'override');
insert into public.deleted_items values (3, '2024-02-01 20:00Z', null, 'archive');
\ir ../migrations/20260923000100_deadline_trigger.sql
\ir ../migrations/20260923000200_deadline_backfill.sql
\ir ../migrations/20260923000300_deadline_validate.sql
\ir ../migrations/20260923000400_deadline_not_null.sql

do $$
declare r record;
begin
  for r in select * from (values
    ('2026-01-17 20:00Z', '2026-01-31'),
    ('2026-01-18 20:00Z', '2026-02-28'),
    ('2024-02-01 20:00Z', '2024-02-29'),
    ('2026-12-20 20:00Z', '2027-01-31'),
    ('2026-01-18 07:59:59Z', '2026-01-31'),
    ('2026-01-18 08:00:00Z', '2026-02-28'),
    ('2026-03-08 09:59:59Z', '2026-03-31'),
    ('2026-03-08 10:00:00Z', '2026-03-31')
  ) as cases(created, expected) loop
    if public.automatic_pickup_deadline(r.created::timestamptz) <> r.expected::date then
      raise exception 'Date calculation failed: %', r;
    end if;
  end loop;
  if (select manual_due_date from public.items where id = 1) <> date '2026-02-28'
    or (select manual_due_date from public.items where id = 2) <> date '2026-04-01'
    or (select manual_due_date from public.deleted_items where id = 3) <> date '2024-02-29'
    or (select count(*) from public.items) <> 2 then
    raise exception 'Backfill changed explicit dates or failed';
  end if;
end $$;

-- Exercise the null payloads emitted by current main, plus omitted columns.
insert into public.items (id, manual_due_date) values (4, null);
insert into public.items (id) values (5);
update public.items set title = 'unrelated edit' where id = 2;
do $$ begin
  if (select manual_due_date from public.items where id = 2) <> date '2026-04-01' then
    raise exception 'Unrelated edit changed deadline';
  end if;
end $$;
update public.items set manual_due_date = null where id = 2;
insert into public.deleted_items select * from public.items where id = 2;
insert into public.deleted_items (id, created_at, manual_due_date)
values (6, '2026-01-18 20:00Z', null);
update public.deleted_items set manual_due_date = null where id = 6;

do $$ begin
  if (select manual_due_date from public.items where id = 2) <> date '2026-02-28'
    or (select manual_due_date from public.deleted_items where id = 2) <> date '2026-02-28'
    or exists (select 1 from public.items where manual_due_date is null)
    or exists (select 1 from public.deleted_items where manual_due_date is null)
    or exists (select 1 from information_schema.columns
      where table_schema = 'public' and table_name in ('items', 'deleted_items')
      and column_name = 'manual_due_date' and is_nullable <> 'NO') then
    raise exception 'Null-client compatibility or constraints failed';
  end if;
  if (select array_agg(id) from (select id from public.items
      order by manual_due_date, created_at, id limit 2) s) <> array[1,2] then
    raise exception 'Stable due-date ordering failed';
  end if;
end $$;

-- An archive can lack its creation timestamp only if it has an explicit deadline.
insert into public.deleted_items (id, manual_due_date) values (7, '2026-09-30');
do $$ begin
  begin
    insert into public.deleted_items (id) values (8);
    raise exception 'Expected missing creation timestamp to be rejected';
  exception when not_null_violation then null;
  end;
end $$;

-- Date calculations must not depend on the SQL client's timezone.
set timezone = 'Asia/Tokyo';
do $$ begin
  if public.automatic_pickup_deadline('2026-01-18 07:59:59Z') <> date '2026-01-31' then
    raise exception 'Session timezone changed deadline';
  end if;
end $$;
