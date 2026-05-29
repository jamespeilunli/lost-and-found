# Library Inventory

An unofficial SvelteKit app for managing library lost-and-found inventory. Anyone can browse active found items anonymously, while whitelisted librarians can log items, update statuses, set pickup deadlines, archive records, and manage librarian access.

## Features

- Anonymous public inventory view with search
- Librarian-only Google sign-in
- Librarian email whitelist management
- Found item logging with optional image upload
- Item statuses: `found`, `claimed`
- Automatic pickup deadlines with optional manual overrides
- Archived item view for librarians
- Light/dark mode

## Routes

- `/` - public inventory and librarian dashboard
- `/log-found` - log a found item
- `/edit/[id]` - edit an inventory item
- `/librarians` - manage librarian email whitelist
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
- `item-images` storage bucket
- `librarian_emails` table
- Whitelist RPCs from `supabase/migrations/20260528000000_privacy_inventory_refactor.sql`
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
