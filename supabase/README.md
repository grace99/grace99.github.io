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

### Start fresh with dues and payments

`operations/purge_financial_records.sql` is a destructive, explicitly invoked operation, not a migration. It removes all rows from `villaDues`, then all rows from `VillaPmt`, including split receipts and transactions, in one locked transaction. Run the complete file as project administrator in Supabase SQL Editor. Export the tables first if a copy needs to be retained. It preserves villa master data, other app data, membership, schema, policies, guards, and identity sequences. Avoid running it during data imports or association updates. Both returned counts should be zero; then refresh the app. Fresh payment imports should use verified villa numbers, positive amounts and actual payment dates, leaving generated IDs and split metadata to the database unless importing intentionally assigned IDs. PaymentStatus defaults to Unmatched. Load monthly dues through the app to set Unpaid/NIL consistently.

### Financial history tables

Run `010_financial_history.sql` after 009 and **before fresh imports**. It creates `VillaPmtHistory` and `villaDuesHistory`. Each event stores complete `old_record` / `new_record` JSON rows, operation (`SNAPSHOT`, `INSERT`, `UPDATE`, `DELETE`), timestamp, signed-in user UUID when available, database login and transaction ID. Separate history IDs allow multiple versions of the same payment or composite due key. History has no foreign keys to live rows, so it survives deletion/purging. New columns are automatically included in subsequent snapshots. The live payment uniqueness constraint is not copied into history.

An installation snapshot records any existing rows; reinstallation preserves history without duplicating the initial snapshot. Previous changes/deletions cannot be reconstructed retroactively. Committed imports, matching, reversal, split creation and direct SQL changes are recorded. Unchanged updates are skipped. Rolled-back or rejected operations leave no history events. SQL Editor operations may have no signed-in user UUID; database login still identifies the connection account.

Only association admins can read history through authenticated browser access. Anonymous, resident and editor access is denied; app users cannot directly insert, edit or delete history. Project database owners still have administrative control. No History page is added by this migration; view the history tables in Supabase.

The supported `operations/purge_financial_records.sql` uses DELETE and now preserves each deleted row in history. TRUNCATE on live finance tables is rejected because it bypasses row auditing. Do not purge history when resetting live financial data. Validation: `tests/check-financial-history-postgres.cjs` with PGlite covers current schemas, snapshots, reinstall, matching/splits/reversal, deletion, user attribution, role access, rollback, additional columns and truncate protection.

### Splitting payments across villas

Apply `011_split_payments_across_villas.sql` after 010, then deploy the frontend. Each split allocation has a destination villa, billing month and positive amount. Multiple villas may receive portions for the same month; one villa may receive portions for different months. Use at most one portion for each villa/month pair. Combined identifiers such as `25-26-27` remain a single permanent villa account.

The selected amounts must exactly equal the original receipt. Each portion receives a new payment ID, selected Villa, AllocationMonth and amount, while retaining receipt date, account, method, purpose, remarks, UTR and late-payment flag. All destinations must exist in villaMaster. The original receipt retains its Villa and amount and is excluded from balances as a split parent. Existing rows are not reassigned. Matching checks the child's own villa and month; reverting releases credit to that child. History records the original's split flag and each new child, including destination Villa.

Existing same-villa monthly splitting remains supported; old callers that omit the allocation villa default to the original Villa. Applied receipts and split children cannot be split again. Retry returns existing child IDs. The live payment uniqueness constraint can reject an allocation matching an existing villa/amount/receipt-date/month combination; the entire split rolls back and the dialog reports the conflict.

Checks: `node --test tests/*.test.cjs`; optional `tests/check-cross-villa-split-postgres.cjs` (PGlite) and `tests/check-cross-villa-split-browser.cjs` (Playwright, `FERNS_TEST_URL`). They cover same-month different villas, exact conservation, receipt preservation, invalid villas, duplicates, collisions/rollback, retries, history, matching restrictions, reversal and mobile layout.

### Map or correct an unapplied payment's villa

Apply `012_map_unassigned_payments.sql` after 011. Record payment now allows **Unassigned — map later** (Villa NULL); imported receipts can also leave Villa NULL. The grid labels these as Unassigned and offers that Villa filter. Unassigned payments have Map villa and Split payment actions; applying a payment requires a confirmed villa.

**Map villa** explicitly assigns or corrects the villa of an unapplied transaction while retaining its ID, amount, dates and receipt details. Admin/editor access is required. The RPC locks the row and checks the expected old Villa, destination master record, existing due links and archive flag. Applied transactions and archived split receipts are rejected; unapplied split children may be corrected while retaining their billing month and original receipt link. A payment uniqueness conflict rolls back the mapping. History records old/new Villa and actor. Same-target retries are harmless.

The payment-villa guard remains enabled. Mapping uses a temporary exception restricted to the selected payment ID and restores it afterwards; collateral changes to other payments are rejected. Manual database villa changes still require the explicit administrator correction transaction described above. Splitting an unassigned original is allowed if every portion explicitly selects a valid destination; the archived original retains NULL Villa.

Checks: `tests/check-payment-villa-mapping-postgres.cjs` and `tests/check-payment-villa-mapping-browser.cjs`, plus the unit suite. They verify unassigned recording, explicit correction, stable identity/receipt data, history, stale or applied rejection, uniqueness conflicts, no collateral guard bypass, split support, filtering, mobile layout and role access.

### Partial payments and financial villa balances

Apply `013_partial_payment_allocations.sql` after 012, then deploy this frontend before using partial matching. There are now three financial structures:

- `villaBalances`: one row per permanent villa account, keyed by `Villa` and referencing `villaMaster.Villa`. Its `outstandingBalance` is maintained automatically from **all** outstanding dues for that villa. New master records automatically receive a financial account. App users cannot edit this balance directly.
- `villaDues`: the existing `villa` column is now a foreign key to `villaBalances.Villa`. The migration adds `paidAmt` (maintained from allocations) and generated `outstandingAmt = max(dueAmt - paidAmt, 0)`. Original `dueAmt` remains unchanged. No balance fields are added to master data.
- `villaPaymentAllocations`: records the amount from each payment applied to a due, using the existing composite due identity and a payment foreign key. One due can receive several payments and one payment can cover several dues. `villaDues.PmtId` remains a reference payment ID; allocations are authoritative for the complete payment list and amounts.

An ₹800 payment against a ₹1,200 due leaves paidAmt ₹800 and outstandingAmt ₹400. After applying migration 015, the due is **Partially paid** until fully covered, then **Cleared**; dues with no payment remain **Unpaid** and zero dues remain **NIL**. The next assessment adds its own due amount, while the old ₹400 remains on the original due and contributes to the villa's all-time balance. Debts are not duplicated into new dues. Unallocated payment credit is tracked separately until applied.

Both matching entry points allow explicit positive partial amounts within available payment credit and outstanding due. Batch allocation commits all selected portions together or rolls back. Expected paid amounts reject stale repeated requests. Existing same-villa and split billing-month checks remain enforced. Revert now reverses **all allocations for the selected due**, including partial payments, restoring credit to each receipt while preserving other dues. Applied payments cannot be mapped or split even if they are not the due's reference payment.

Use **Dues → Villa balances** for older outstanding, latest loaded month's outstanding, and the all-time total per villa. Click the total to inspect the underlying unpaid dues. Date-filtered Overview cards retain their reporting-month rule; the balance view always includes older debt. Villa directory remains master data only.

Existing valid full matches are backfilled as allocations without changing receipt amounts or villa assignments. Installation aborts on inconsistent links or overallocated receipts. History captures allocation creation/changes/deletion in `villaPaymentAllocationHistory`, alongside existing due/payment history. The provided DELETE purge removes live allocations through the due foreign key, resets financial balances to zero and retains history.

For imports, continue using the payment schema previously supplied. Do not supply computed `paidAmt`/`outstandingAmt` or manually load PmtId matches into new dues; use the matching workflow. Only admin/editor RPCs can write allocations. All members can read permitted financial records; allocation history is admin-only.

Validation: `node --test tests/*.test.cjs`, `tests/check-partial-payments-postgres.cjs` (PGlite), and `tests/check-partial-payments-browser.cjs` (Playwright, `FERNS_TEST_URL`). They cover partial/top-up/full status transitions, multi-receipt reversal, credit conservation, batch rollback, history, foreign keys, new account creation, balance totals, role access, purge, both UI entry points and monthly carry-forward.

## 014 — Admin center and database audit

Run [014_admin_center.sql](014_admin_center.sql) **after 013**, then merge the accompanying app into main. Run the entire file, including BEGIN/COMMIT. It adds `fernsvilla_audit_events`, admin-only read access, row-change/truncate audit triggers on `VillaPmt`, `villaDues`, `villaMaster`, `villaPaymentAllocations`, `villaBalances`, `fernsvilla_state` and `fernsvilla_members`, and a successful-sign-in trigger on `auth.users.last_sign_in_at`. No auth credentials or auth user snapshots are copied. An admin/editor-only monthly-dues wrapper logs billing date, inserted/skipped/eligible counts and tags the resulting row events with the same transaction ID. The private original loader is no longer directly callable by authenticated users.

Existing financial histories are imported once; rerunning 014 does not duplicate them or overwrite logs. Sign-ins and nonfinancial activity start being captured after installation. The feed is newest-first, loaded in batches of 100 with timestamp/ID cursors, and filters apply to loaded events. Users can refresh or load older events. Database SQL with no user JWT is attributed to the database role. Failed sign-ins, historical sign-in logs, DDL, SELECTs and unmonitored tables are not included. Existing protections that reject financial TRUNCATE remain in place. This migration creates database triggers, including one on auth.users, so apply it from Supabase SQL Editor with the project’s database-owner permissions; no service-role key belongs in the browser.

## 015 — Partially paid status

Run the complete [015_partially_paid_due_status.sql](015_partially_paid_due_status.sql) after 013 and after 014 if Admin center is installed. It replaces the existing due-status trigger function and updates existing processed records: zero due → NIL; no payment → Unpaid; payment below the due amount → Partially paid; full payment → Cleared. Existing allocations, due/payment amounts, links and outstanding balances are retained. Further matching, top-ups, reversals and direct SQL allocation changes use the same server-side status rules. Status updates are captured by existing history/audit triggers. Reruns skip unchanged records. No new columns are required.

## 016 — Self-registration and resident blog access

Run [016_signup_resident_access.sql](016_signup_resident_access.sql) after 014 and 015, before deploying sign-up (014 is required for the approval queue and audit capture). Pending app registrations are captured from auth.users without granting membership; metadata cannot assign a role. Email confirmation updates the request. Admin center offers verified requests for approval through an admin-only RPC that grants resident access and preserves existing roles on retries. The registrations table is read-only to clients (own request or admins) and its changes are audited. Existing marked app registrations are backfilled on installation; reruns preserve approvals.

Residents may publish to the community blog via `fernsvilla_add_post`; it validates inputs, derives author identity from auth.users and atomically appends to posts, preserving all other association-state sections and incrementing the revision. It grants no financial/master/team/resource write access. Read access needed by Overview drilldowns is retained. Enable email sign-ups and Confirm email in Supabase, and allow redirect `https://grace99.github.io/?signup=confirmed`. No secret key is used in the app.

## 017 — Dedicated community issues

Run the complete [017_community_issues.sql](017_community_issues.sql) after 016 and before merging the app. It creates the table if missing and supports the manually created schema. Adds a unique legacy import identifier, imports JSON issues once, preserves the original JSON, and audits subsequent issue DML. Existing resolved legacy issues receive an explicit migration note because their resolution details/date were not captured; their resolution timestamp is the import time. Their original villa/location text is retained as location, avoiding unverified villa links. Reruns do not overwrite imported or edited issues.

Members can read issues; admins/editors can write. The UI requires resolution details and date for Resolved/Closed, and uses optimistic concurrency on `updated_at`. The trigger preserves reporter identity and creation time, records the resolving user, and clears resolution date/user when reopened. The browser does not write issues back into JSON; unrelated content saves retain the legacy array unchanged.

## 018 — Issues and preventive maintenance views

Run the complete [018_issue_record_type.sql](018_issue_record_type.sql) after 017, before deploying the two-view UI. Adds `community_issues.record_type`, defaulting existing and future records to `Issue`, with allowed values `Issue` and `Preventive maintenance`. Existing category, severity, recurrence, resolution, permissions, and audit capture remain in use. Reruns preserve classifications. The form lets admins/editors reclassify records; views maintain independent filters and per-view totals. Overview Open issues and its community issues list include only Issue records. This adds classification, not automatic scheduling or recurring task generation.
