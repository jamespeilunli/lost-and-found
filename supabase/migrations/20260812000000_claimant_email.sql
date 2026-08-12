-- Store the latest claimant email without exposing it to anonymous inventory reads.
-- Existing librarian-only RLS policies continue to govern authenticated access.

alter table public.items
  add column if not exists claimed_by_email text;

alter table public.deleted_items
  add column if not exists claimed_by_email text;

revoke select (claimed_by_email), insert (claimed_by_email), update (claimed_by_email)
on public.items
from anon;

grant select (claimed_by_email), update (claimed_by_email)
on public.items
to authenticated;
