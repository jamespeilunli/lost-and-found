-- Allow librarians to restore (unarchive) items: move a row back out of
-- deleted_items into items.
--
-- Two permission gaps are closed here:
--  1. public.deleted_items had no delete grant/policy, so the archived copy
--     could never be removed after a restore.
--  2. The existing public.items insert grant (20260529_forward_privacy_repair)
--     is column-restricted and omits id, created_at, and claimed_by_email.
--     A restore must preserve the item's original id, creation time (the pickup
--     countdown is derived from it), and last-claimant email, so those columns
--     must be insertable. RLS still limits all of this to librarian emails.

grant delete on public.deleted_items to authenticated;

grant insert (id, created_at, claimed_by_email) on public.items to authenticated;

drop policy if exists "Librarians can delete archived inventory" on public.deleted_items;

create policy "Librarians can delete archived inventory"
on public.deleted_items
for delete
to authenticated
using ((select public.is_librarian_email()));
