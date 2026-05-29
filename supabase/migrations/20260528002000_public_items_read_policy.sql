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

drop policy if exists "Public can read found inventory" on public.items;

create policy "Public can read found inventory"
on public.items
for select
to anon, authenticated
using (status = 'found');
