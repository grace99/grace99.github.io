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
