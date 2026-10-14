# Deadline rollout

Apply the database changes before deploying this branch. Do not replay historical
migrations: the privacy repair migration contains deletions.

## Preflight and staging

1. Confirm a current recoverable production backup exists.
2. Run `deadline_preflight.sql` in the Supabase SQL Editor and save/export results.
   Expect `manual_due_date` to be `date` on `items` and `deleted_items`, and
   `created_at` to be `timestamptz`: `items` has a non-null default, while
   `deleted_items` allows null and has no default. Archive writes copy the original
   creation timestamp. Stop if another table has this column, a row has both a
   null deadline and null creation timestamp, types differ, or
   existing triggers alter these fields; resolve those differences first.
3. Test on a staging copy with the same schema/triggers/RLS. Run the four new
   migrations below, then connect the current production `main` build to staging.
   Verify blank create, custom create, clear override, unrelated edit, status
   change, and archive all succeed. A previously automatic deadline now appears
   populated in the edit form. Old clients retain their existing list ordering.
   Local SQL tests supplement this gate; they do not verify the live schema/RLS.

## Production execution

Run these files individually, in order, in SQL Editor. Each file commits its own
short transaction. Do not wrap all files in one transaction.

1. `20260923000100_deadline_trigger.sql`
2. `20260923000200_deadline_backfill.sql`
3. `20260923000300_deadline_validate.sql`
4. `20260923000400_deadline_not_null.sql`

On any error, stop; roll back an open failed transaction before retrying the
failed file. Do not rerun already committed files. Lock timeouts fail safely
instead of waiting indefinitely. If the backfill hits its 30-second timeout,
keep the old app deployed and arrange a batched backfill before proceeding.
Record these migrations as applied in your normal migration tracking workflow
if SQL Editor execution is outside that workflow.

Run `deadline_verify.sql` and the preflight again. Expect zero null deadlines,
`is_nullable = NO`, preserved explicit dates, and unchanged row counts except
for legitimate concurrent user activity. Then deploy the new app and smoke-test
public/librarian/archive pagination and search. Due dates sort ascending, then
creation timestamp, then id; search still prioritizes relevance.

## Compatibility and rollback

The trigger resolves omitted or explicitly null dates BEFORE constraints run,
including null writes from the current `main` create/edit forms and archive
copies. Clearing a date recalculates from the original creation timestamp.
Explicit dates survive all updates. No columns or policies are removed or renamed.
Automatic dates use Pacific calendar dates plus 14 days, then month end.
The updated app interprets deadline expiration as the end of that Pacific day.

If app rollout fails, redeploy the previous app and keep the database changes.
Do not revert backfilled dates to null. Monitor Supabase errors and failed
create/edit/archive operations after rollout. Actual production/main staging
compatibility remains a required operator check before running production SQL.
