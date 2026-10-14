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

## Dues and Payments tables

The app now reads `villaDues` and `VillaPmt` directly. Apply `004_dues_payments.sql` in the Supabase SQL Editor before deploying this version. It uses the existing table schemas supplied for this project, adds membership policies and two guarded database functions, and leaves existing rows intact. Live installation cannot be performed from this workspace without project administration access.

- **Dues:** grid columns are `villa`, `dueTyp`, `dueDesc`, `dueAmt`, `dueDate`, `dueStatus`, and `PmtId`. Linked payment details appear directly below the due. Special funds use an administrator-entered fund/type name; the unique `(villa, dueTyp, dueDate)` key means two same-type funds on the same date must use distinct descriptive type names.
- **Monthly bulk load:** choose a month and due date, preview villas and totals, then load. Amounts are read on the server from `villaMaster.MaintAmount` (the actual column name). Combined villa identifiers are preserved as one billable account. Null/zero maintenance amounts are excluded except Under construction villas, which load at ₹0. `dueTyp` is `Monthly maintenance`; status starts `Unpaid` (or `NIL` for zero-amount construction dues). Existing monthly dues for the same villa and calendar month are skipped, even when the chosen day changes. Historical records using other type names should be reconciled before bulk loading their month.
- **Payments:** grid and entry form follow `VillaPmt`'s schema; its generated `id` is displayed as the selectable PmtId. Payment entry records receipts and does not automatically clear dues. All fields except the generated ID can be supplied; villa, date and amount are required.
- **Matching:** choose a payment for the same permanent villa account with enough remaining balance. The database locks both payment and due, rechecks available credit, and updates `PmtId` and `dueStatus = Cleared` together. One payment can clear several dues. This schema supports one linked payment per due; combining partial payments into a single due requires a separate allocation table and is not implemented.
- **Credit:** all amounts already linked through `PmtId` are deducted from the payment's available balance. Payments are never counted once per linked due. Financial totals and charts now use the relational records, not the legacy villa snapshot. No old JSON payment data is silently migrated into `VillaPmt`.
- **Permissions:** residents can read. Admins/editors can create records and call the functions. Existing policies must not permit clients to bypass guarded matching with unrestricted direct UPDATEs; review any pre-existing write policies before deployment.

After installation, verify an admin can load dues, record a special-fund due and payment, clear two dues with one sufficiently large payment, and rerun a monthly load without duplicates. A resident must not create, clear, or bulk-load dues.

Local checks: `node --test tests/*.test.cjs` uses no additional dependencies. The PostgreSQL integration runner `tests/check-dues-postgres.cjs` needs `@electric-sql/pglite` in Node's module path; the optional browser runner `tests/check-finance-browser.cjs` needs Playwright, Chromium at `/usr/bin/chromium`, and the app served at port 8000. These test dependencies are not required to run the static app. Browser responses are simulated; PostgreSQL functions and RLS are executed locally against test tables, separately from live Supabase verification.

## Split payments between billing months

Apply `005_payment_splitting.sql` after `004_dues_payments.sql`, then deploy the updated frontend. This additive migration introduces `AllocationMonth` (billing month), `SplitFromPmtId` (original receipt ID), and `IsSplitParent` (retained original receipt). It does not change existing payment amounts or due links during installation.

On Payments, choose **Split payment** for an unapplied original transaction. Enter at least two distinct billing months and manually assign an amount to each. Positive portions must total the original amount exactly, to the cent. Every portion receives a new generated payment ID. The same villa, receipt date, account, method, purpose, UTR, remarks, and late-payment flag are copied unchanged. Billing months are separate from the receipt date.

The original record keeps its full receipt amount and is retained as an original split receipt for audit. It cannot be applied to dues and is excluded from transaction totals, available credit, charts, and export totals. The default Payments filter shows transactions; select **Original split receipt** under Record type to view retained originals. The Original payment ID column identifies the shared receipt. Date basis can switch between receipt date and billing month.

Splitting is atomic and locks the same payment row as due matching. Any payment already linked to a due is blocked from splitting, preserving its existing relationships. Child transactions cannot be split again. Retrying a completed split returns its existing IDs and creates no duplicate amounts. Each child can fund multiple dues for its same villa and allocated month within its available balance.

Validation: `node --test tests/*.test.cjs`; optionally run `tests/check-payment-split-postgres.cjs` with PGlite and `tests/check-payment-split-browser.cjs` with Playwright. The database runner checks preservation of receipt details, total conservation, safe retries, invalid totals/months, already-applied payments, monthly matching, archived originals, and member roles. Live Supabase installation and validation remain pending project-admin execution of the migration.

## Revert a cleared due

Apply `006_revert_due_payment.sql` after `005_payment_splitting.sql`. Admins and editors see **Revert** on cleared due rows. The confirmation identifies the villa, due, amount and payment before **Revert allocation**.

The database locks the expected payment first, then the due, matching the lock order of application and splitting. It checks the original due amount and payment link, clears `villaDues.PmtId`, and restores `dueStatus` to `Unpaid` in one transaction. A safe retry of an already Unpaid/unlinked due releases no additional amount. A changed amount, status or linked payment is rejected.

`VillaPmt` stores receipts, not a mutable applied-balance column: the original apply operation only set the due link. Its complete inverse therefore removes that link and recalculates the payment's available balance from the remaining linked dues. Receipt amount, UTR, date, split information and generated payment IDs remain intact. Other cleared dues using the same payment are unaffected. Reverting a split transaction's due restores that child's credit within its assigned month; it does not merge or delete the split transactions.

Both financial record sets are reloaded after reversal, updating the Dues and Payments grids and summary amounts. If a read fails after the database reversal commits, the UI reports that the reversal completed and asks for Refresh rather than suggesting another reversal.

Checks: `node --test tests/*.test.cjs`, plus the optional PGlite runner `tests/check-due-reversal-postgres.cjs` and Playwright runner `tests/check-due-reversal-browser.cjs`. The database test verifies preserved receipts and other allocations, restored normal/split credit, safe retries, stale-data rejection, reapplication, and resident denial. Live Supabase verification remains pending installation of the migration.

### Under construction

Run `007_under_construction_dues.sql` after `006_revert_due_payment.sql`. The villa form uses **Residence status**, including **Under construction**, which sets maintenance to ₹0. A database trigger enforces that amount on master inserts and maintenance/status updates. Monthly loading includes those villas with `dueAmt = 0`, even if an older master record still has a positive amount; repeated loads remain protected against duplicates. The preview shows the exemption and the dues grid shows **No payment required**. Existing dues and payment allocations are preserved. Changing back to another residence status enables entry of the applicable maintenance amount. Special fund entries retain their separately entered amounts.

Validation: `node --test tests/*.test.cjs` and `tests/check-construction-postgres.cjs` with PGlite. Project-admin execution of the migration is required for live Supabase enforcement.

### Due and payment statuses; matching from Payments

Run `008_payment_matching_status.sql` after `007_under_construction_dues.sql`, then deploy this frontend. It uses the existing `VillaPmt.PaymentStatus` column (adding it as text only if absent), normalizes existing due statuses, and synchronizes existing payment statuses from actual `villaDues.PmtId` links. Amounts and payment links are retained. Due statuses are **Unpaid**, **NIL** for ₹0, and **Cleared** when applied. New special dues also start Unpaid; reverting returns a positive due to Unpaid.

The Payments grid displays and filters **Payment status**. **Apply payment** selects one or more eligible dues for the same villa, with date/month filters and sorting. Split transactions are restricted to their allocated month. The selected dues must fit within the available balance and clear together in one database transaction; failure leaves all selections unchanged. A payment is **Matched** if any due references it, including when it has remaining credit. Reverting the final linked due changes it to **Unmatched**; reverting one of several links leaves it Matched. New receipts and split transactions start Unmatched; archived split originals cannot be applied.

Validation: `node --test tests/*.test.cjs`, plus `tests/check-payment-matching-postgres.cjs` (PGlite) and `tests/check-payment-matching-browser.cjs` (Playwright; optional `FERNS_TEST_URL`). These cover existing status normalization, zero dues, atomic allocation/rollback, both matching entry points, partial/last reversal, split-month rules, and resident denial. Live Supabase installation requires project-admin execution of migration 008.

### Protect payment villa assignments

Apply `009_protect_payment_villa.sql` after 008 to reject changes to an existing payment's Villa. The guard checks all updates after BEFORE triggers have run, so an unintended villa reassignment rolls back the transaction. Matching/status changes, receipt-date corrections and payment splitting still work. Existing records are untouched; this is containment, not a repair of earlier changes.

Verified administrator corrections require an explicit, transaction-local opt-in: `SET LOCAL fernsvilla.allow_payment_villa_correction = 'on'` inside a transaction containing narrowly scoped, reviewed updates. Confirm original payment-to-villa assignments from receipts or a pre-incident export before preparing a repair. A due link alone is not proof of the original payment villa. The opt-in ends when the transaction ends.

Read-only incident queries are in `supabase/diagnostics/`: `payment_matching_functions.sql` inspects deployed function bodies, `payment_matching_rules.sql` inspects rewrite rules, and `payment_matching_cross_villa.sql` lists inconsistent links. Run each file separately so the SQL Editor displays its results. Validate containment with `tests/check-payment-matching-postgres.cjs` (PGlite).
