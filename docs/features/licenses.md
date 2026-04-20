# Feature: Licenses

## Description

The Licenses feature is the second of three domain modules (certificates, licenses, dashboard) and gives organisations a single place to track software licenses, subscriptions, contracts, and any other time-bound paid agreement they need to renew.

Licenses share the same minimal shape as certificates — name, expiration date, responsible person, provider, cost, and notes — but are a distinct entity: a separate table, a separate module flag, and a separate view. Keeping them separate avoids the temptation to shoehorn unrelated items into one list and gives us room to grow license-specific fields (seat count, license key, vendor URL, renewal cadence) in later iterations without touching the certificates schema.

Scope is intentionally tight: this feature only handles license-level CRUD. Aggregated metrics, renewal reminders, and cross-module analytics are **out of scope** and will arrive with the upcoming Dashboard feature (feature #3).

The module is gated behind the mandator profile system (`module_licenses`) and follows the same enable/disable pattern as all other ERP modules.

## Deliverables

### Database — `licenses` table

Stores a single license scoped to a mandator.

| Column | Type | Constraints |
| --- | --- | --- |
| `id` | UUID | PK, default `gen_random_uuid()` |
| `mandator_id` | UUID | NOT NULL, FK → `mandators(id)` ON DELETE CASCADE |
| `name` | TEXT | NOT NULL — display name of the license |
| `expires_at` | DATE | NOT NULL — expiration / renewal date |
| `responsible_user_id` | UUID | FK → `profiles(id)` ON DELETE SET NULL — person responsible for renewal |
| `provider` | TEXT | — issuing vendor (e.g. Microsoft, JetBrains) |
| `cost` | NUMERIC(12, 2) | — cost of the license (nullable) |
| `notes` | TEXT | — freeform notes |
| `created_by` | UUID | FK → `auth.users(id)` |
| `updated_by` | UUID | FK → `auth.users(id)` |
| `created_at` | TIMESTAMPTZ | DEFAULT `now()` |
| `updated_at` | TIMESTAMPTZ | DEFAULT `now()`, with existing `set_updated_at` trigger |

Indexes:
- `idx_licenses_mandator_id` on `(mandator_id)` — membership lookups.
- `idx_licenses_expires_at` on `(mandator_id, expires_at)` — sorted list + expiration queries.

Note: `responsible_user_id` references `public.profiles(id)` (not `auth.users`) so PostgREST can embed the profile in SELECT queries (same pattern established for `certificates`). `profiles.id` already cascades from `auth.users`, so the semantic chain is preserved.

RLS policies (all scoped to `auth.uid()` being a member of `mandator_id` via `get_user_mandator_ids()`):
- SELECT: members of the mandator can read.
- INSERT: members of the mandator can create, and `mandator_id` must match a mandator they belong to.
- UPDATE: members of the mandator can update.
- DELETE: members of the mandator can delete. (Admin-only deletion is deferred until there is a product case for it.)

### Database — `mandators` table extension

Add the following column to the existing `mandators` table:

| Column | Type | Constraints |
| --- | --- | --- |
| `module_licenses` | BOOLEAN | NOT NULL, DEFAULT `true` |

### Database — helper function: `get_license_summary(p_mandator_id uuid)`

Returns a single-row aggregate used by the licenses list header and, later, by the Dashboard feature. Mirrors `get_certificate_summary` for consistency.

```sql
CREATE OR REPLACE FUNCTION public.get_license_summary(p_mandator_id uuid)
RETURNS TABLE (
    total_count          INTEGER,
    expiring_soon_count  INTEGER,
    expired_count        INTEGER
) AS $$
    SELECT
        COUNT(*)::INTEGER AS total_count,
        COUNT(*) FILTER (
            WHERE expires_at >= current_date
              AND expires_at <= current_date + INTERVAL '30 days'
        )::INTEGER AS expiring_soon_count,
        COUNT(*) FILTER (WHERE expires_at < current_date)::INTEGER AS expired_count
    FROM public.licenses
    WHERE mandator_id = p_mandator_id;
$$ LANGUAGE sql STABLE SECURITY DEFINER;
```

Note: `SECURITY DEFINER` bypasses RLS inside the function; the composable only calls it for the currently-selected mandator, so the caller is already known to be a member.

### Composable — `useLicenses`

A new composable at `web/src/composables/useLicenses.ts` that mirrors `useCertificates` for a separate entity:

- Exposes `licenses` (ref array), `summary` (ref object or `null`), `loading` (ref boolean) state.
- Provides `fetchLicenses(mandatorId)` — fetches all licenses for the given mandator, ordered by `expires_at` ascending (most urgent first). Embeds the responsible profile via `responsible:responsible_user_id(id, email, display_name)`.
- Provides `getLicense(id)` — fetches a single license with embedded responsible profile (used by the detail view).
- Provides `createLicense(mandatorId, form)`, `updateLicense(id, form)`, `deleteLicense(id)` — CRUD. `created_by` / `updated_by` are populated from the current session; `mandator_id` is passed explicitly. `deleteLicense` prompts for confirmation at the view layer, not here.
- Provides `fetchLicenseSummary(mandatorId)` — calls the `get_license_summary` RPC and stores the result in `summary`. Returns fields: `total_count`, `expiring_soon_count`, `expired_count`. Used by the licenses list header banner and the future Dashboard.

### Composable — `useMandator` extension

Extend the existing `useMandator` composable with:

- A new reactive flag: `licensesEnabled` (computed from `mandator.module_licenses`).
- Add `'licenses'` to the `enabledModules` computed list when the flag is active (automatic via `MODULE_DEFINITIONS`, noted here for completeness).
- Register the new module in the `MODULE_DEFINITIONS` array (in `src/modules/index.ts`):
  ```ts
  { route: 'licenses', column: 'module_licenses', label: 'Licenses' }
  ```
- `isModuleEnabled('licenses')` returns the correct value.

### Navigation and routing

- In `App.vue`, the nav item for "Licenses" pointing to `/licenses` is rendered automatically by the existing `MODULE_DEFINITIONS` iteration — no manual nav entry is required.
- Add authenticated routes in `router/index.ts`:
  ```ts
  { path: '/licenses', name: 'licenses', component: LicensesView, meta: { requiresAuth: true, module: 'licenses' } }
  { path: '/licenses/:id', name: 'licenses-detail', component: LicenseDetailView, meta: { requiresAuth: true, module: 'licenses' } }
  ```

### View — `LicensesView.vue` (list)

The top-level page for the feature: a sortable list of all licenses for the active mandator.

- Header with:
  - Page title "Licenses".
  - Summary pills (driven by `summary`): "Total: N", "Expiring: N" (warning), "Expired: N" (error). Rendered via `SyvoraBadge`.
  - Primary action: "Add license" button (`SyvoraButton`, `:full="isMobile"`) — opens a `SyvoraModal` with the create form.
- List of licenses with responsive layout (same pattern as Certificates):
  - **Desktop (>600px)**: table with columns Name (linked to `/licenses/:id`), Expires (formatted `20 Apr 2027`), Responsible (display name → email → "—"), Status badge.
  - **Mobile (≤600px)**: card list. Each card is a `SyvoraCard` wrapping a `RouterLink` to `/licenses/:id`, with the license name + status badge on top (flex-wrap, no overflow), then labelled rows for Expires and Responsible.
- Status badge logic: `success` "Valid" (>30 days), `warning` "Expiring" (≤30 days, ≥0 days), `error` "Expired" (<0 days).
- Empty-state (`SyvoraEmptyState`): "No licenses yet. Add one to start tracking renewal dates."
- "Add license" modal fields (minimal create form):
  - Name (`SyvoraInput`, required).
  - Expiration date (`SyvoraInput` type `date`, required).
  - Responsible person (native `<select>` styled to match, populated from `useMandator().members`, optional).
  - Footer: "Cancel" (`variant="ghost"`) + "Add" (disabled until name + date are set).

### View — `LicenseDetailView.vue` (edit + full details)

Full edit surface for a single license. All fields editable inline.

**Basics**:
- Name (required), Expiration date (required), Responsible person (dropdown of mandator members).
- "Save" button (`SyvoraButton`) persists changes; "Delete" button (variant `ghost`, with confirm) removes the license and routes back to `/licenses`.

**Additional details**:
- Provider (`SyvoraInput`).
- Cost (`SyvoraInput` type `number`, `suffix` "CHF" for currency label).
- Notes (`SyvoraTextarea`, max ~2000 chars, `SyvoraFormField` `char-count` + `max-chars` for the live counter).

**Status panel**:
- Status badge (same logic as list view).
- "Days until expiration" or "Days overdue" derived from `expires_at`.
- Last updated timestamp (locale-formatted).

Navigation: breadcrumb-style "← Back to licenses" link at the top; unsaved-changes warning is out of scope.

Responsive:
- At ≤600px: cards stack to one column, title + badge stack, and action buttons become full-width column-reverse (Save on top, Delete below). Same pattern used for `CertificateDetailView`.

### Admin UI — mandator management extension

- In the mandator create/edit modal within `AdminView.vue`:
  - A "Licenses" checkbox is added automatically via `MODULE_DEFINITIONS` — no manual AdminView edit needed, the existing loop renders it.
- The mandator list view displays a "Licenses" badge (enabled/disabled) consistent with existing module badges — also automatic.

### Sensible defaults

- The migration sets `module_licenses = true` on all existing mandator records so the feature is available immediately without manual admin intervention.
- The registration push into `MODULE_DEFINITIONS` happens in `web/src/modules/index.ts` so the nav entry, admin toggle, and route guard all light up together.
- On license creation, `created_by` and `updated_by` are populated from the current session; `mandator_id` is sourced from the active mandator — the user never selects these manually.

## Definition of Done

- The `licenses` table exists with the specified schema, indexes, foreign keys (with `responsible_user_id` referencing `profiles(id)`), `set_updated_at` trigger, RLS policies scoped by mandator membership, and the `get_license_summary` helper function.
- The `licenses` table is added to the `supabase_realtime` publication, matching the certificates pattern.
- The `mandators` table has `module_licenses` (BOOLEAN, default `true`).
- The `useLicenses` composable provides reactive state and CRUD operations plus a summary fetch backed by the RPC.
- The `useMandator` composable exposes `licensesEnabled` and `'licenses'` is registered in `MODULE_DEFINITIONS` via `src/modules/index.ts`, so it appears automatically in `enabledModules`.
- A new "Licenses" tab appears in navigation when the module is enabled for the current mandator.
- Navigating to `/licenses` or `/licenses/:id` when the module is disabled redirects to the home view (existing router guard).
- The user can create a license with name, expiration date, and an optional responsible person from a modal on `/licenses`.
- The user can open `/licenses/:id` to edit full details (provider, cost, notes) and delete the license with confirmation.
- The list view shows status badges (Valid / Expiring / Expired) derived from `expires_at` and a summary header backed by `get_license_summary`.
- The admin can toggle the Licenses module per mandator via `AdminView.vue` (no manual AdminView code change required).
- All existing mandators are migrated with `module_licenses = true` (no breaking change on deploy).
- Toggling the module flag takes effect without a full page reload (via `refreshMandator()`).
- The list and detail views are responsive down to 320px (iPhone SE 1st gen), reusing the patterns established for certificates: flex-wrap on the name/badge row, `word-break: break-word` on long values, full-width primary action on mobile.
- The `get_license_summary` RPC returns the same counts the upcoming Dashboard feature will consume — no schema change is expected when the Dashboard is built.
