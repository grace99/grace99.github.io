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

When no public Supabase key is configured, the app starts in a separate demo mode with illustrative community data. Edits and payment records are saved to this browser's local storage under `fernsvilla-v1`; they are not shared across devices or users. CSV export downloads the current villa dues ledger. October 2026 is the sample assessment period; May–September chart figures are illustrative historical data. Policies and service contacts are examples and should be verified before operational use.

The app has Supabase email/password authentication, member access controls, and shared versioned storage. Online payment processing and recurring monthly billing are not implemented. A proper period-based dues ledger and more granular resident permissions remain production requirements. Google Fonts are optional; system fonts work when unavailable.

## Validation

Chromium smoke checks covered all nine pages, villa creation, payment recording and credit calculation, local persistence after reload, community post publication, issue status transitions, and desktop/mobile layouts. JavaScript syntax was checked with `node --check app.js`.

Supabase UI integration checks use simulated API responses; live `villaMaster` column reads passed; authenticated live writes and policy verification remain pending.
