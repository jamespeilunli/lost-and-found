# Lost and Found

A SvelteKit app for managing library lost-and-found items. Students can report lost items and browse the inventory, while librarians can log found items, update statuses, archive records, and manage librarian access.

Production: https://mvhs-lost-and-found.vercel.app

## Features

- Public inventory view with search
- Student sign-in and lost item reporting
- Librarian-only found item logging
- Item statuses: `lost`, `found`, `claimed`
- Optional image upload for items
- Edit/delete for a user's own reports
- Archived item view for librarians
- Librarian role management
- Light/dark mode

## Routes

- `/` - inventory dashboard
- `/submit` - report a lost item
- `/log-found` - log a found item
- `/edit/[id]` - edit an existing item
- `/librarians` - manage librarian roles
- `/about` - static about page

## Stack

- SvelteKit
- Svelte 5
- TypeScript
- Tailwind CSS 4
- shadcn-svelte / Bits UI
- Supabase Auth, Database, and Storage

## Required Supabase Setup

The app expects:

- `items` table
- `deleted_items` table
- `profiles` table
- `item-images` storage bucket
- `list_profiles_with_email` RPC
- `set_profile_role` RPC
- Google OAuth enabled in Supabase Auth

## Environment Variables

Create a `.env` file:

```bash
PUBLIC_SUPABASE_URL=your_supabase_project_url
PUBLIC_SUPABASE_ANON_KEY=your_supabase_anon_key
```

## Development

Install dependencies:

```bash
npm install
```

Run the dev server:

```bash
npm run dev
```

Run checks:

```bash
npm run check
```

Build for production:

```bash
npm run build
```

Preview the production build:

```bash
npm run preview
```
