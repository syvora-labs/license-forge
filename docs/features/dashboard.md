# Feature: Dashboard

## Description

The Dashboard is the third and final module in the initial product set (certificates, licenses, dashboard) and **becomes the application's home page** — the landing view every authenticated user sees at `/`. It replaces the previous placeholder `HomeView`, which is removed as part of this feature.

It answers the two questions users care about most: *what's about to expire*, and *what's this costing us*. Nothing else — no task management, no audit log, no notifications; those are out of scope for this iteration.

The Dashboard is **not a new entity** — it is a read-only aggregation view over the existing `certificates` and `licenses` tables. It deliberately introduces no new domain data so any module added later can plug in without schema coordination.

Because the Dashboard is the home page, it is **not gated by a module flag**. Unlike `certificates` and `licenses`, there is no `module_dashboard` column and no entry in `MODULE_DEFINITIONS`. It is always visible to authenticated users. If a user has no enabled modules, they still see the dashboard — it simply renders empty states.

The focus is visual: rather than another sortable table, the Dashboard uses simple, self-contained CSS-driven visualisations (stacked bars for status distribution, horizontal proportional bars for cost) so the user can spot the most urgent or most expensive items at a glance. Every item rendered — in the urgency list, in the cost breakdown, anywhere a name appears — is a clickable link to the corresponding `/certificates/:id` or `/licenses/:id` detail page.

## Deliverables

### Database — no changes

The Dashboard introduces **no new tables and no new columns**. It reads from `public.certificates` and `public.licenses` via the existing RLS policies and the existing `get_certificate_summary` / `get_license_summary` RPCs. Any new aggregates needed are computed client-side from those sources.

No migration file is required for this feature.

### Composable — `useDashboard`

A new composable at `web/src/composables/useDashboard.ts` that composes the existing `useCertificates` and `useLicenses` and derives a single dashboard-shaped payload:

- Exposes:
  - `loading` (ref boolean) — true while any sub-fetch is in flight.
  - `upcoming` (computed array) — combined certs + licenses with `expires_at ≤ today + 60 days`, sorted ascending by `expires_at`. Each item is normalised to `{ id, type: 'certificate' | 'license', name, expires_at, responsible, cost, status, href }` where `href` is `/certificates/:id` or `/licenses/:id`.
  - `topByCost` (computed array) — top 10 items from both tables with a non-null `cost`, sorted descending by `cost`. Each item carries the same `href` so the bar is clickable.
  - `totalCost` (computed number) — sum of all non-null `cost` values across certs + licenses.
  - `certStatusBreakdown` / `licenseStatusBreakdown` (computed `{ valid, expiring, expired, total }`) — counts for the stacked-bar status chart per type. Derived from the existing summary RPCs.
- Provides `refresh(mandatorId)` — fan-out fetch:
  - `fetchCertificates(mandatorId)` + `fetchLicenses(mandatorId)` (for the full lists, powering `upcoming` and `topByCost`)
  - `fetchCertificateSummary(mandatorId)` + `fetchLicenseSummary(mandatorId)` (for the status breakdowns)

All four fetches run in parallel via `Promise.all`. No new Supabase RPCs are added.

### Composable — `useMandator`

**No extension required.** The Dashboard is not a toggleable module, so no `dashboardEnabled` flag and no `MODULE_DEFINITIONS` entry.

### Navigation and routing

- **Delete `web/src/views/HomeView.vue`.** It is fully superseded by `DashboardView`.
- Replace the existing `/` route so it renders the new `DashboardView`:
  ```ts
  { path: '/', name: 'home', component: DashboardView, meta: { requiresAuth: true } }
  ```
  Keep `name: 'home'` — any existing `{ name: 'home' }` redirects across the app (router guards, post-login, module-disabled redirects) remain valid without changes.
- No `meta.module` on this route — the dashboard is always available.
- No `/dashboard` alias — `/` is the canonical path. Avoids having two URLs for the same page.
- In `App.vue`, the existing "Home" nav link pointing to `/` remains unchanged. It now leads to the dashboard.

### View — `DashboardView.vue` (home / aggregate overview)

The single page for the feature, rendered at `/`. Layout is a vertical stack: a small personalised greeting, then cards.

**Greeting (top of page)**:
- "Welcome, {display_name or email}" (reuses the personalised greeting from the deleted `HomeView` so we don't regress the warm landing experience).
- Subline: the active mandator name in muted text.

**Stat cards (2×2 grid on desktop, 1-col on mobile)**:
- **Certificates**: total count with a small stacked-bar sparkline (valid / expiring / expired segments, coloured `success` / `warning` / `error`). Whole card is a `RouterLink` to `/certificates`.
- **Licenses**: same structure, links to `/licenses`.
- **Expiring in 7 days**: single number (certs + licenses combined, from the two summary RPCs).
- **Total cost**: single number formatted as `CHF 12'345.00` (locale `de-CH`). Sum of all non-null `cost` values.

**Expiring soon card (full width)**:
- Title: "Expiring in the next 60 days".
- Renders `upcoming` (up to 20 items) as a list of rows. Each row:
  - Type badge: "Cert" or "License" via `SyvoraBadge`.
  - Name — bold, clickable, navigates to `href`.
  - Responsible display name (fallback email, fallback "—").
  - Right-aligned: formatted expiration date + `daysLabel` ("in 12 days" / "3 days overdue" / "today").
  - Status badge (`success` / `warning` / `error`) — same logic used in the list views.
- Each row is fully clickable (wrap the row in a `RouterLink`).
- Empty state (`SyvoraEmptyState`): "Nothing expiring in the next 60 days."

**Cost breakdown card (full width)**:
- Title: "Top 10 items by cost".
- Renders `topByCost` as horizontal proportional bars. Each bar:
  - Left: type badge + name (clickable link to detail).
  - Bar fill: width = `cost / maxCost * 100%`, colour `--color-accent` for licenses, `--color-accent-dim` for certificates.
  - Right: formatted cost `CHF 1'200.00`.
- The whole row is a `RouterLink`, so clicking the name OR the bar navigates.
- Empty state: "No cost data yet. Add cost to a certificate or license to see it here."

**Status distribution card (full width)**:
- Title: "Status distribution".
- Two horizontal stacked bars, one per type:
  - Bar 1: "Certificates" — one 100%-wide bar with three segments (`success` / `warning` / `error`) whose widths are `valid / total`, `expiring / total`, `expired / total`. Hovering or tapping a segment shows an absolute count (via `title` attribute — no tooltip library).
  - Bar 2: "Licenses" — same structure.
- Each bar has a small legend below: `X valid · Y expiring · Z expired`.

**Empty state for brand-new mandators**:
- When `upcoming`, `topByCost`, and both breakdowns are all empty (zero certs and zero licenses), render a single `SyvoraEmptyState` with a short "Get started" message linking to `/certificates` and `/licenses`. Avoids showing four empty cards to a user who has just created a mandator.

**Responsiveness (down to 320px)**:
- Greeting line wraps; no horizontal scroll.
- Stat grid collapses to 1 column.
- Cost breakdown rows: name stacks above the bar on mobile; cost stays right-aligned.
- Status bars: segment widths remain proportional; the legend wraps.
- All clickable rows use the same full-row-link pattern established in `CertificatesView` / `LicensesView` card mode.

### Admin UI — no changes

No module toggle is added to `AdminView` (the dashboard is always on). The existing admin UI is unchanged.

### Sensible defaults

- The registration step in `web/src/modules/index.ts` is **not** touched — the dashboard is not a module.
- Switching mandators while `/` is open re-fetches dashboard data via a watcher on `mandator.id`, same pattern as `CertificatesView` / `LicensesView`.

## Definition of Done

- `web/src/views/HomeView.vue` is deleted.
- `web/src/views/DashboardView.vue` is created and rendered at `/` with `name: 'home'` preserved so all existing `{ name: 'home' }` redirects continue to work.
- No new database tables, columns, or migrations are introduced. All data is read from `certificates` and `licenses` via existing RLS and RPCs.
- The `useDashboard` composable exposes `loading`, `upcoming`, `topByCost`, `totalCost`, `certStatusBreakdown`, `licenseStatusBreakdown`, and a `refresh(mandatorId)` method.
- `useMandator` and `MODULE_DEFINITIONS` are unchanged — the dashboard is not a gated module.
- Navigating to `/` after login shows the dashboard. No `/dashboard` alias exists.
- `DashboardView` renders the greeting, four stat cards, the expiring-soon list, the cost-breakdown bars, and the two status-distribution bars.
- Every item-level name and every cost bar is a clickable link that navigates to `/certificates/:id` or `/licenses/:id`.
- The stat cards for "Certificates" and "Licenses" navigate to `/certificates` and `/licenses` respectively.
- When the active mandator has zero certificates and zero licenses, a single "Get started" empty state is shown instead of four empty cards.
- The page is responsive down to 320px (iPhone SE 1st gen): stat grid collapses to 1 column, bars reflow, no horizontal scroll.
- No chart libraries or additional dependencies are added — visualisations are pure CSS using existing design tokens.
- Switching mandators while on the dashboard re-fetches the data (watcher on `mandator.id`).
- No new `get_dashboard_*` RPCs are required. If performance becomes a concern with large datasets, a server-side aggregate can be added later without changing the view's public contract.
