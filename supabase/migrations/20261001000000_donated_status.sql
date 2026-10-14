alter table public.items
  drop constraint items_status_check,
  add constraint items_status_check check (status in ('lost', 'found', 'claimed', 'donated'));
