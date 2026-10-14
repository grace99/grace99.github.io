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

When no public Supabase key is configured, the app starts in a separate demo mode with illustrative community data. Edits and payment records are saved to this browser's local storage under `fernsvilla-v1`; they are not shared across devices or users. CSV export downloads aggregate villa dues and payment totals. Separate Dues and Payments pages use the existing `villaDues` and `VillaPmt` tables. Apply `supabase/004_dues_payments.sql` to enable monthly bulk loading and payment matching. Live charts use relational due/payment dates for the most recent six months. Policies and service contacts are examples and should be verified before operational use.

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

Overview contains no headline, Record payment shortcut, Export report shortcut or Recent dues section. Export report is available on Dues. Total villas counts individual numeric plots within permanent hyphenated groups (25-26-27 counts as three); its sub-stat shows only under-construction plots. Account identifiers remain unchanged. The villa drilldown shows both individual plot and source villa account.

Overview finance cards use the previous calendar month throughout the current calendar month, based on the browser's local date. Payments received uses receipt date and excludes archived split parents; outstanding dues uses due date and positive uncleared amounts. Cards display the reporting month. Other finance pages retain their filtered or all-time totals.

Stat cards on Overview, Analytics, Dues and Payments open read-only drilldown grids with column labels, relevant filters, date/month controls and sorting. Modal filters do not change the parent page's filters or data. Tests: `node --test tests/*.test.cjs` and the optional Playwright `tests/check-overview-browser.cjs` (`FERNS_TEST_URL`).

The six-month dues collection trend groups payment allocations and remaining outstanding amounts by due date month, including partial payments. Receipt dates do not affect the trend. Each paid/unpaid bar opens its corresponding allocation/dues grid; totals and collection rate cover the displayed months.

Grids use compact filter ribbons, month buttons, row spacing and finance summaries. Row actions have visible button borders, icons and explanatory hover tooltips. Finance action columns remain visible during horizontal scrolling, and unmatched dues omit empty payment-detail rows. The Overview browser check verifies that directory, dues and payment rows fit in the opening view at 1366 × 768.
