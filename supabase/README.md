# Supabase connection

Project: `exrhpaqpepubscyqflov`
Endpoint: `https://exrhpaqpepubscyqflov.supabase.co`

The public publishable key is configured in `config.js`. It is intended for browser use. Never replace it with a secret or service-role key.

## Initialize the project

1. Open this project’s Supabase SQL Editor and run `001_association.sql`. The migration creates dedicated `fernsvilla_members` and `fernsvilla_state` tables and a save function. It starts with empty association data and does not upload browser demo data or modify unrelated tables.
2. In Supabase Authentication → Users, create or invite the association administrator. Set a password using Supabase’s account setup flow. If using invitations, configure the appropriate Site URL and redirect URL for your hosted site. The app currently supports email/password sign-in; use a password configured through Supabase.
3. Copy that account’s user UUID, then run the following in the SQL Editor, replacing the placeholder:

```sql
insert into public.fernsvilla_members (user_id, role)
values ('REPLACE_WITH_AUTH_USER_UUID'::uuid, 'admin')
on conflict (user_id) do update set role = excluded.role;
```

4. Open the app and sign in. Add real villas, committee members, service contacts and posts. No sample data is automatically copied to the server.
5. Invite additional users through Supabase Authentication and grant membership using the same SQL with `editor` or `resident`. Association team entries are directory records; they do not grant login access. Membership changes are restricted to the SQL Editor/backend administrator.

## Access model

- Unauthenticated users cannot read or write association records.
- `resident` members may view records. `admin` and `editor` members may edit all records in this version.
- Villa directory records are read, created and edited directly in the existing case-sensitive `public."villaMaster"` table. Other shared data is stored in one versioned JSONB association document. Saves use an atomic revision check; a stale save fails without overwriting newer data. Press **Refresh**, then repeat the change. This is suitable for the current small app; separate relational tables are recommended for larger deployments and finer resident-level permissions.
- Direct client writes to the association document are denied. Its writes use the `fernsvilla_save` function. Villa directory inserts and edits use authenticated PostgREST requests to `villaMaster`, subject to its grants and RLS policies.
- Browser sessions persist on the device. Use **Sign out** on shared devices. Production hosting should use HTTPS.
- Failed cloud requests do not fall back to local storage or display success. Form entries stay available for retry. Cloud association records are not copied into the demo local-storage key.

## Verify after project setup

1. Signed out: attempts to edit or export association data are blocked.
2. Sign in as an administrator, add a villa and record a payment. Reload and sign in from another browser; both clients must show the saved balance.
3. Sign in as a resident. Records should load and edits should be denied by both UI and database.
4. Sign in with an account without membership. It must not load association data.
5. Open two editor sessions, save a change in one, then try to save from the other without refreshing. The stale save must fail and preserve the latest server data.

Live `villaMaster` reads with the supplied column names returned HTTP 200. Authenticated live writes and database policy verification remain pending; no project-administration connection or user account credentials are available. Browser create/edit and payment checks use simulated responses, separately from live service verification.

## Repeatable adapter tests

Run `node --test tests/supabase.test.cjs` from the repository root. These dependency-free tests exercise authenticated requests, nonmember denial, resident read-only access, save conflict handling, session refresh/sign-out, and rejection of secret keys. They use simulated responses and do not verify live database policies.

## Existing villaMaster directory

`config.js` maps the app to the supplied table without renaming or recreating it:

| App field | Database column |
| --- | --- |
| Villa number / stable primary key | `Villa` |
| Resident name | `Name` |
| Owner/renter | `OwnORrent` |
| Occupancy status | `ResStatus` |
| Monthly assessment | `MaintAmount` |
| Address | `Area`, `Street` |
| Household counts | `NumRes`, `NumKids`, `NumVehicles`, `NumPets` |
| Property flags/status | `OwnCCTV`, `OwnPwrLine`, `Ostatus` |
| Phone numbers | `PriPhoneNo`, `SecPhoneNo` |
| Email addresses | `PriEmailAdd`, `SecEmailAdd` |

The generated bigint `id` is left to Supabase; the primary key is `Villa`. Editing cannot change the villa number because the dues ledger references it. Nullable fields may remain blank; zero and false values are preserved. Existing custom status values are retained in edit forms. Reads paginate beyond a single 500-row page. Edits compare the original column values and report stale or inaccessible updates rather than claiming success.

If existing table policies already provide member read and editor insert/update access, leave them unchanged. If permissions are missing, review and run `002_villa_master_access.sql` after the membership migration. This optional script checks for unknown existing policies and stops without changes if found; reconcile those policies through the SQL Editor. It does not recreate the table or alter its rows.

Villa directory changes never call `fernsvilla_save`. For other saves, that document keeps only villa-number-linked assessment/payment balances; contact and directory fields are not copied back into JSON. Existing JSON-only directory entries are not silently imported into `villaMaster`; add or import those master records explicitly. Their recorded balances remain retained and join by `Villa` when matching master records exist.

Run all adapter checks with `node --test tests/*.test.cjs`. Authenticated deployment validation should verify that a saved directory record appears in Supabase Table Editor and is visible from a second authorized browser.
