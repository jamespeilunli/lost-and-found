-- Forward-only hardening for the email/password librarian invite rewrite.
-- The app no longer calls whitelist mutation RPCs from the browser; librarian
-- invite/removal happens through SvelteKit server endpoints using service role.

drop trigger if exists on_auth_user_created on auth.users;
drop trigger if exists handle_new_user on auth.users;
drop trigger if exists create_profile_on_signup on auth.users;
drop function if exists public.handle_new_user();
drop function if exists public.create_profile_for_user();

drop policy if exists "Public can read found inventory" on public.items;
drop policy if exists "Librarians can read inventory" on public.items;
drop policy if exists "Librarians can create inventory" on public.items;
drop policy if exists "Librarians can update inventory" on public.items;
drop policy if exists "Librarians can delete inventory" on public.items;
drop policy if exists "Librarians can read archived inventory" on public.deleted_items;
drop policy if exists "Librarians can create archived inventory" on public.deleted_items;
drop policy if exists "Librarians can read whitelist" on public.librarian_emails;
drop policy if exists "Librarians can add whitelist emails" on public.librarian_emails;
drop policy if exists "Librarians can remove whitelist emails" on public.librarian_emails;

revoke all on public.librarian_emails from anon, authenticated;
revoke execute on function public.list_librarian_emails() from anon, authenticated;
revoke execute on function public.add_librarian_email(text) from anon, authenticated;
revoke execute on function public.remove_librarian_email(text) from anon, authenticated;
revoke execute on function public.require_librarian() from anon, authenticated;
revoke execute on function public.current_user_email() from anon, authenticated;
revoke execute on function public.normalize_librarian_email(text) from anon, authenticated;

grant execute on function public.is_librarian_email() to anon, authenticated;

drop function if exists public.add_librarian_email(text);
drop function if exists public.remove_librarian_email(text);
drop function if exists public.list_librarian_emails();
drop function if exists public.require_librarian();
drop function if exists public.normalize_librarian_email(text);

create policy "Public can read found inventory"
on public.items
for select
to anon
using (status = 'found');

create policy "Librarians can read inventory"
on public.items
for select
to authenticated
using ((select public.is_librarian_email()));

create policy "Librarians can create inventory"
on public.items
for insert
to authenticated
with check ((select public.is_librarian_email()));

create policy "Librarians can update inventory"
on public.items
for update
to authenticated
using ((select public.is_librarian_email()))
with check ((select public.is_librarian_email()));

create policy "Librarians can delete inventory"
on public.items
for delete
to authenticated
using ((select public.is_librarian_email()));

create policy "Librarians can read archived inventory"
on public.deleted_items
for select
to authenticated
using ((select public.is_librarian_email()));

create policy "Librarians can create archived inventory"
on public.deleted_items
for insert
to authenticated
with check ((select public.is_librarian_email()));

drop table if exists public.profiles;
