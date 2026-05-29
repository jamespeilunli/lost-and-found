-- Privacy-focused inventory refactor:
-- - librarians are controlled by email whitelist
-- - anonymous users can only read active found inventory through a public view
-- - old lost reports are removed from active inventory
-- - librarians can override automatic pickup due dates per item

alter table public.items
  add column if not exists manual_due_date date;

alter table public.deleted_items
  add column if not exists manual_due_date date;

create table if not exists public.librarian_emails (
  email text primary key,
  created_at timestamptz not null default now(),
  created_by uuid null
);

alter table public.librarian_emails enable row level security;

do $$
begin
  if to_regclass('public.profiles') is not null then
    insert into public.librarian_emails (email, created_by)
    select distinct lower(trim(u.email)), u.id
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.role = 'librarian'
      and u.email is not null
    on conflict (email) do nothing;
  end if;
end $$;

insert into public.deleted_items (
  id,
  title,
  description,
  category,
  status,
  image_url,
  location_found,
  created_at,
  created_by,
  manual_due_date
)
select
  id,
  title,
  description,
  category,
  status,
  image_url,
  location_found,
  created_at,
  created_by,
  manual_due_date
from public.items
where status = 'lost'
on conflict (id) do nothing;

delete from public.items
where status = 'lost';

create or replace function public.current_user_email()
returns text
language sql
stable
as $$
  select lower(nullif(auth.jwt() ->> 'email', ''));
$$;

create or replace function public.is_librarian_email()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.librarian_emails le
    where le.email = public.current_user_email()
  );
$$;

create or replace function public.require_librarian()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_librarian_email() then
    raise exception 'Librarian access required' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.normalize_librarian_email(raw_email text)
returns text
language sql
immutable
as $$
  select lower(trim(raw_email));
$$;

create or replace function public.list_librarian_emails()
returns table (
  email text,
  created_at timestamptz,
  created_by uuid
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.require_librarian();

  return query
  select le.email, le.created_at, le.created_by
  from public.librarian_emails le
  order by le.email asc;
end;
$$;

create or replace function public.add_librarian_email(new_email text)
returns table (
  email text,
  created_at timestamptz,
  created_by uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_email text := public.normalize_librarian_email(new_email);
begin
  perform public.require_librarian();

  if normalized_email is null or normalized_email = '' or normalized_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid email address' using errcode = '22023';
  end if;

  insert into public.librarian_emails (email, created_by)
  values (normalized_email, auth.uid())
  on conflict (email) do update
    set email = excluded.email
  returning librarian_emails.email, librarian_emails.created_at, librarian_emails.created_by
  into email, created_at, created_by;

  return next;
end;
$$;

create or replace function public.remove_librarian_email(target_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_email text := public.normalize_librarian_email(target_email);
begin
  perform public.require_librarian();

  if normalized_email = public.current_user_email() then
    raise exception 'You cannot remove your own librarian email' using errcode = '42501';
  end if;

  delete from public.librarian_emails
  where librarian_emails.email = normalized_email;
end;
$$;

do $$
declare
  existing_policy record;
begin
  for existing_policy in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('items', 'deleted_items', 'librarian_emails')
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      existing_policy.policyname,
      existing_policy.schemaname,
      existing_policy.tablename
    );
  end loop;
end $$;

create policy "Librarians can read whitelist"
on public.librarian_emails
for select
to authenticated
using (public.is_librarian_email());

create policy "Librarians can add whitelist emails"
on public.librarian_emails
for insert
to authenticated
with check (public.is_librarian_email());

create policy "Librarians can remove whitelist emails"
on public.librarian_emails
for delete
to authenticated
using (public.is_librarian_email());

revoke all on public.items from anon;
revoke all on public.deleted_items from anon;
revoke all on public.librarian_emails from anon;
grant usage on schema public to anon, authenticated;
grant select (
  id,
  title,
  description,
  category,
  status,
  image_url,
  location_found,
  created_at,
  manual_due_date
) on public.items to anon, authenticated;
grant select, insert, update, delete on public.items to authenticated;
grant select, insert, update, delete on public.deleted_items to authenticated;
grant select on public.librarian_emails to authenticated;
grant execute on function public.is_librarian_email() to anon, authenticated;
grant execute on function public.list_librarian_emails() to authenticated;
grant execute on function public.add_librarian_email(text) to authenticated;
grant execute on function public.remove_librarian_email(text) to authenticated;

alter table public.items enable row level security;
alter table public.deleted_items enable row level security;

create policy "Librarians can read inventory"
on public.items
for select
to authenticated
using (public.is_librarian_email());

create policy "Public can read found inventory"
on public.items
for select
to anon, authenticated
using (status = 'found');

create policy "Librarians can create inventory"
on public.items
for insert
to authenticated
with check (public.is_librarian_email());

create policy "Librarians can update inventory"
on public.items
for update
to authenticated
using (public.is_librarian_email())
with check (public.is_librarian_email());

create policy "Librarians can delete inventory"
on public.items
for delete
to authenticated
using (public.is_librarian_email());

create policy "Librarians can read archived inventory"
on public.deleted_items
for select
to authenticated
using (public.is_librarian_email());

create policy "Librarians can create archived inventory"
on public.deleted_items
for insert
to authenticated
with check (public.is_librarian_email());

do $$
declare
  existing_policy record;
begin
  for existing_policy in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and (
        coalesce(qual, '') ilike '%item-images%'
        or coalesce(with_check, '') ilike '%item-images%'
      )
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      existing_policy.policyname,
      existing_policy.schemaname,
      existing_policy.tablename
    );
  end loop;
end $$;

create policy "Public can read item images"
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'item-images');

create policy "Librarians can upload item images"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'item-images' and public.is_librarian_email());

create policy "Librarians can update item images"
on storage.objects
for update
to authenticated
using (bucket_id = 'item-images' and public.is_librarian_email())
with check (bucket_id = 'item-images' and public.is_librarian_email());

create policy "Librarians can delete item images"
on storage.objects
for delete
to authenticated
using (bucket_id = 'item-images' and public.is_librarian_email());
