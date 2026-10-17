# FernsVilla Residents Assn.

A responsive static web app for managing villa records, association dues, financial analytics, maintenance and security issues, community policies, committee members, service contacts, and community posts.

## Run locally

From this directory:

```sh
python3 -m http.server 8000
```

Open the served site in a browser. No dependency installation or build is required. The site can be hosted directly on GitHub Pages.

## Data and limitations

The app is configured for Supabase project `exrhpaqpepubscyqflov`. Complete the migration and account membership setup in [supabase/README.md](supabase/README.md) before signing in. Association records are shared through Supabase with authenticated access. Villa directory records use the existing `villaMaster` table; its `MaintAmount` drives dues assessments.

When no public Supabase key is configured, the app starts in a separate demo mode with illustrative community data. Edits and payment records are saved to this browser's local storage under `fernsvilla-v1`; they are not shared across devices or users. CSV export downloads aggregate villa dues and payment totals. Separate Dues and Payments pages use the existing `villaDues` and `VillaPmt` tables. Apply `supabase/004_dues_payments.sql` to enable monthly bulk loading and payment matching. Overview shows the current calendar year by due month; Analytics retains its six-month trend. Policies and service contacts are examples and should be verified before operational use.

The app has Supabase email/password authentication, member access controls, and shared versioned storage. Online payment processing and automatic recurring billing are not implemented; monthly dues can be loaded explicitly in bulk. The dues ledger supports monthly and special-fund assessments, with atomic full-due payment matching. Google Fonts are optional; system fonts work when unavailable.

## Validation

Chromium smoke checks covered all nine pages, villa creation, payment recording and credit calculation, local persistence after reload, community post publication, issue status transitions, and desktop/mobile layouts. JavaScript syntax was checked with `node --check app.js`.

Supabase UI integration checks use simulated API responses; live `villaMaster` column reads passed; authenticated live writes and policy verification remain pending.

## Grid filters and sorting

Record grids use labeled filter panels with Search and Reset. Dues and Payments offer calendar-year filters, inclusive From/To dates, and multi-select month buttons; these filters combine. With All years selected, month buttons match that month across all years. Directory and card grids offer applicable category, role, villa, area, street, or status filters without invented dates.

Click a table header to sort; click it again to reverse direction. Card lists use a Sort by selector and direction button. Villa values use natural numeric ordering, including permanent multi-plot identifiers: `2`, `10`, `25-26-27`, `100`. Amounts and payment IDs use numeric ordering, and date fields use chronological ordering. Dues keep their linked payment details together while sorting. Grid state is separate for each view and remains in memory during navigation.

Dues and Payments summary cards reflect the filtered records. Available payment balances still account for all linked dues, including dues outside the visible date range. Monthly-preview filters only change displayed rows; the load still bills all eligible villas for the selected month. Column captions and forms use readable labels while preserving the original database field mappings.

Run `node --test tests/*.test.cjs` for adapter and filtering checks. The optional `tests/check-grid-browser.cjs` uses Playwright and the local app at port 8000 to check filters, natural sorting, payment matching after sorting, editable card identity, and responsive layouts.

Payments can be apportioned manually between billing months into new payment IDs, preserving the original receipt details. Apply `supabase/005_payment_splitting.sql` before deploying that feature. Only unapplied original payments may be split; portions must total the receipt amount exactly. Retained originals are excluded from totals to avoid duplicate counting.

Cleared dues can be reverted by admins/editors after installing `supabase/006_revert_due_payment.sql`. Reversal resets the due to Pending, removes its payment link, and restores available payment credit while preserving the receipt and other linked dues.

## Appearance

The sun/moon button in the top-right header switches between light and dark themes across pages, grids, forms, account controls and dialogs. On a new browser the theme follows the device preference, including changes while the app is open. Choosing a theme saves it in `ferns-theme` local storage and retains it across navigation and reloads. It requires no Supabase migration.

The optional Playwright check `tests/check-theme-browser.cjs` validates device preferences, saved overrides, all pages, finance dialogs and mobile layout. Set `FERNS_TEST_URL` to the local server URL (defaults to port 8013 for this check).

## Overview and stat drilldowns

Overview contains no headline, Record payment shortcut, Export report shortcut or Recent dues section. Export report is available on Dues. Total villas counts individual numeric plots within permanent hyphenated groups (25-26-27 counts as three); its sub-stat shows only under-construction plots. Account identifiers remain unchanged. The Overview villa drilldown shows one row per villa account, with monthly maintenance and cumulative outstanding balance.

Overview finance cards use the previous calendar month throughout the current calendar month, based on the browser's local date. Payments received uses receipt date and excludes archived split parents; outstanding dues uses due date and positive uncleared amounts. Cards display the reporting month. Other finance pages retain their filtered or all-time totals.

Stat cards on Overview, Analytics, Dues and Payments open read-only drilldown grids with column labels, relevant filters, date/month controls and sorting. Modal filters do not change the parent page's filters or data. Tests: `node --test tests/*.test.cjs` and the optional Playwright `tests/check-overview-browser.cjs` (`FERNS_TEST_URL`).

The dues collection trend groups payment allocations and remaining outstanding amounts by due date month, including partial payments. Receipt dates do not affect the trend. Overview uses one stacked bar per month: paid allocations at the bottom and remaining dues above them. Each colored segment opens its corresponding allocation/dues grid; totals and collection rate cover the displayed months.

Grids use compact filter ribbons, month buttons, row spacing and finance summaries. Grid row actions use compact icon-only buttons with visible borders, accessible action labels and explanatory hover tooltips. Finance action columns remain visible during horizontal scrolling, and unmatched dues omit empty payment-detail rows. The Overview browser check verifies that directory, dues and payment rows fit in the opening view at 1366 × 768.

Dues and Payments have a Columns picker in the grid header. Payments initially hides Account number, Late payment, Billing month, Original payment ID and Record type; Dues initially hides Due type. Choices persist separately in browser local storage. Reset columns restores each grid’s defaults. Payment ID and the due’s Villa remain visible. Both grids default to ascending numeric Villa sorting. Column visibility does not affect filtering, allocation matching or exported data.

## Admin center

Admin center appears at the bottom of the menu for signed-in administrators. Apply `supabase/014_admin_center.sql` after 013 to enable its read-only activity feed. The feed includes successful Supabase sign-ins, transaction creation/modification/deletion, payment allocations and balances, monthly dues-load summaries, villa-directory and association-content changes, membership changes, and direct SQL DML on those monitored tables. Event details show changed fields, before/after values, actor or database role, and transaction ID. Filters, sorting and dates apply to loaded events; use Load older events to extend the feed. Times and date filters use the browser’s local timezone.

Financial history already retained by migrations 010/013 is imported once. Other changes and sign-ins are captured from installation onward; failed sign-ins, earlier sign-in history, schema changes and unrelated database tables are outside this feed. Supabase sign-ins are captured through updates to `auth.users.last_sign_in_at`, without storing auth rows, passwords or tokens. Table audit events are committed or rolled back with the original DML. App users, including admins, cannot write audit events; only admins can read them. SQL Editor changes without a user JWT identify the database role instead of inventing a resident identity. Privileged database operators can bypass triggers; this is a database activity feed, not an external tamper-proof audit service.

Migration 014 retains the monthly-load implementation behind an editor/admin-only wrapper that adds a summary event; it does not change payment/dues columns or amounts. Existing financial history and truncate protection remain intact. Run migrations in numeric order. Checks: `node --test tests/*.test.cjs`, PostgreSQL regression `tests/check-partial-payments-postgres.cjs` (PGlite), and Playwright `tests/check-admin-browser.cjs` (`FERNS_TEST_URL`).

The light theme uses warm sage backgrounds and softly tinted surfaces for cards, grids, filters and dialogs, with darker text and clearer chart fills to reduce glare. Theme browser checks cover both palettes and normal-text contrast in the finance view.

Apply `supabase/015_partially_paid_due_status.sql` after 013 (and 014 when installed). Dues are NIL for zero amounts, Unpaid with no allocations, Partially paid when allocated amounts are below the due amount, and Cleared when fully paid. The migration updates already processed statuses, retains balances and allocations, and safely reruns. Top-ups and reversals derive status from the remaining allocations.

## Password recovery on GitHub Pages

The sign-in form includes Forgot password? Users enter their email, follow the Supabase recovery email and set/confirm a new password. Recovery sessions are verified against Supabase Auth before saving, work independently of association membership, and are removed locally after the password update; users then sign in normally. Membership and roles are unchanged. Invalid/expired links offer a new reset email. Recovery tokens are removed from the address bar on arrival, and the form can resume after a reload.

Publish this branch to `main` first. In Supabase → Authentication → URL Configuration, use Site URL `https://grace99.github.io/` and add the exact Redirect URL **`https://grace99.github.io/?reset-password=1`**. This root URL is correct for the `grace99/grace99.github.io` user-site repository; there is no CNAME file. `config.js` uses the public URL even when requesting an email from a workspace preview. Supabase sends the email using the project’s email/SMTP configuration and password policy; its standard recovery-email template should link through the Supabase confirmation URL so the app receives the recovery session. No SQL migration or service-role key is required. Browser regression: `tests/check-password-reset-browser.cjs` (`FERNS_TEST_URL`).

The Dues Amount collected card sums amounts applied to all filtered dues, including Partially paid items. Amount collected plus Outstanding dues equals Total dues. Its drilldown lists the corresponding payment allocations, and top-ups/reversals refresh the totals. Unallocated payment credit is excluded.

Browser assets in `index.html` use content-hash URL versions so GitHub Pages/CDN caches request the correct JavaScript and styles after deployment. After editing any referenced JS/CSS/SVG file, run `node scripts/update-asset-versions.cjs` and commit `index.html` with the change; the unit suite checks that versions match file contents. Publishing still requires a successful GitHub Pages deployment from main. If the public UI does not reflect a merge, check repository Actions → pages build and deployment and Settings → Pages → main / (root).

Hover or keyboard-focus either segment of an Overview stacked bar to see the month’s exact paid and outstanding amounts. Paid amounts include allocations against both Cleared and Partially paid dues; only the unpaid remainder contributes to Outstanding. Unallocated receipts are excluded, and both series use due month.

## Self-registration and resident access

Apply `supabase/016_signup_resident_access.sql` after 015 before publishing this UI. Enable email sign-ups and Confirm email in Supabase Authentication settings. Add `https://grace99.github.io/?signup=confirmed` to Authentication → URL Configuration → Redirect URLs (keep the password-reset URL). Create an account is available from Sign in. Registration requires full name, email and matching passwords; users confirm their email, then an administrator approves the pending request under **Admin center → Registrations**. Approval grants resident membership only; existing higher roles are preserved. Existing manually created auth accounts can still be granted membership by an administrator as before.

Overview is above the Management menu grouping. Residents have Overview and its read-only stat/chart drilldowns, plus view-only Guidelines & policies, Association team and Helpful resources. Community blog allows publishing stories. Management pages and editing controls are blocked for residents. Underlying overview data remains readable to approved members to support the requested drills. Financial writes and whole-document association updates remain restricted to admin/editor at the database layer. The resident blog function only appends a validated story, stamps the authenticated identity and increments revision so concurrent stale admin saves cannot overwrite a new story; it cannot replace team/resources or alter financial records. Tests cover signup, approvals, role restrictions and publication (`tests/check-resident-browser.cjs`, the full PostgreSQL regression and unit tests).

Overview uses a full-width Jan–Dec chart with collection rate beside its title, followed by Community noticeboard, Community issues and Around the neighbourhood. Payment and outstanding-dues card drilldowns start on the cards’ reporting month but let all approved roles, including residents, select other years/months without leaving Overview. Titles and rows follow that selection. Payment drilldowns show concise columns and Villa/status filters; outstanding-dues drilldowns keep Year/month controls without From/To dates. Matched/Unmatched payment statuses render as green/amber badges in both drilldowns and the Payments grid.

The Total villas report includes the assessment note “Monthly dues assessed at ₹1 per sq ft effective Jan 2026, as approved on 11 January 2026 GB meeting”, labels area as Total area sq ft, and shows small informational icons for zero maintenance (Under construction) and vacant accounts. Residence-status filtering is removed from this report. Policies keep fixed numbering and source order without sample labels or sorting controls; Association team also retains source order with no sorting controls.

Villa status icons use larger glossy red styling and immediate hover/focus tooltips. The amber assessment note emphasizes the rate/effective date and uses a slow pulse, disabled when the device requests reduced motion.

Overview Payments received reports omit Payment ID and Payment method columns, and both monthly finance reports use Year/month selection without date ranges. Overview Outstanding dues reports also omit the Due type column.

Community issues now use the dedicated `community_issues` table rather than the shared JSON state. Apply the complete `supabase/017_community_issues.sql` before deploying this app version. It supports the table already created manually, imports legacy issues once without deleting the JSON source, and enables audit capture. Admins/editors can report and edit issues, including category, severity, recurrence, location, reporting details, target resolution, status, and resolution. Residents retain read-only Overview access.

The Issues & maintenance page now has separate Issues and Preventive maintenance views with independent filters/counts and a Record type form field. Apply `supabase/018_issue_record_type.sql` after 017 before deploying. Existing records default to Issue; administrators/editors can change their classification.

Payment-side matching shows all due types/statuses for the selected villa across the current month and previous 11 calendar months, newest due date first. Only outstanding items compatible with an allocated billing month can be selected. The modal offers freeform search, a year dropdown alongside month buttons, and Reset. Apply and Split banners show purpose and full remarks as plain values; grid headers stay visible while their table bodies scroll.

Grid scrolling is preserved through checkbox redraws, filter changes, and page updates after payment actions. The payment-matching ribbon places the year dropdown and month buttons together without extra search-panel padding.

Scroll preservation covers same-view redraws throughout the app: table bodies, modal containers, month ribbons, column-picker panels, sidebar, and card-page document position. Grid identities keep positions attached to their own views when panels are inserted. Monthly-preview updates and split-row edits also preserve modal position. When results shrink, scrolling clamps to the available content.
