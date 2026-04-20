# Feature: Certificates

## Description

The Certificates feature is the first of three domain modules (certificates, licenses, dashboard) and provides the foundation for tracking compliance documents, SSL certificates, ISO certifications, and any other time-bound credential an organisation needs to renew.

Users create certificates with the essentials — name, expiration date, and a responsible person — and can optionally attach provider, cost, and notes for context. The scope is intentionally tight: this feature only handles certificate-level CRUD. Aggregated metrics, renewal reminders, and cross-module analytics are **out of scope** and will arrive with the upcoming Dashboard feature (feature #3).

The module is gated behind the mandator profile system (`module_certificates`) and follows the same enable/disable pattern as all other ERP modules.

## Deliverables

### Database — `certificates` table

Stores a single certificate scoped to a mandator.

| Column | Type | Constraints |
| --- | --- | --- |
| `id` | UUID | PK, default `gen_random_uuid()` |
| `mandator_id` | UUID | NOT NULL, FK → `mandators(id)` ON DELETE CASCADE |
| `name` | TEXT | NOT NULL — display name of the certificate |
| `expires_at` | DATE | NOT NULL — expiration date |
| `responsible_user_id` | UUID | FK → `auth.users(id)` ON DELETE SET NULL — person responsible for renewal |
| `provider` | TEXT | — issuing authority or vendor |
| `cost` | NUMERIC(12, 2) | — cost of the certificate (nullable) |
| `notes` | TEXT | — freeform notes |
| `created_by` | UUID | FK → `auth.users(id)` |
| `updated_by` | UUID | FK → `auth.users(id)` |
| `created_at` | TIMESTAMPTZ | DEFAULT `now()` |
| `updated_at` | TIMESTAMPTZ | DEFAULT `now()`, with existing `set_updated_at` trigger |

Indexes:
- `idx_certificates_mandator_id` on `(mandator_id)` — membership lookups.
- `idx_certificates_expires_at` on `(mandator_id, expires_at)` — sorted list + expiration queries.

RLS policies (all scoped to `auth.uid()` being a member of `mandator_id`):
- SELECT: members of the mandator can read.
- INSERT: members of the mandator can create, and `mandator_id` must match a mandator they belong to.
- UPDATE: members of the mandator can update.
- DELETE: members of the mandator can delete. (Admin-only deletion is deferred until there is a product case for it.)

### Database — `mandators` table extension

Add the following column to the existing `mandators` table:

| Column | Type | Constraints |
| --- | --- | --- |
| `module_certificates` | BOOLEAN | NOT NULL, DEFAULT `true` |

### Database — helper function: `get_certificate_summary(p_mandator_id uuid)`

Returns a single-row aggregate used by the certificates list header and, later, by the Dashboard feature. Computes counts based on the current date.

```sql
CREATE OR REPLACE FUNCTION public.get_certificate_summary(p_mandator_id uuid)
RETURNS TABLE (
    total_count          INTEGER,
    expiring_soon_count  INTEGER,
    expired_count        INTEGER
) AS $$
    SELECT
        COUNT(*)::INTEGER                                                           AS total_count,
        COUNT(*) FILTER (
            WHERE expires_at >= current_date
              AND expires_at <= current_date + INTERVAL '30 days'
        )::INTEGER                                                                  AS expiring_soon_count,
        COUNT(*) FILTER (WHERE expires_at < current_date)::INTEGER                  AS expired_count
    FROM public.certificates
    WHERE mandator_id = p_mandator_id;
$$ LANGUAGE sql STABLE SECURITY DEFINER;
```

Note: `SECURITY DEFINER` bypasses RLS inside the function, but the caller must still be a member of the mandator at the application layer — the composable only calls this for the currently-selected mandator.

### Composable — `useCertificates`

A new composable at `web/src/composables/useCertificates.ts` that:

- Exposes `certificates` (ref array), `summary` (ref object or `null`), `loading` (ref boolean) state.
- Provides `fetchCertificates(mandatorId)` — fetches all certificates for the given mandator, ordered by `expires_at` ascending (most urgent first). Resolves `responsible_user_id` to display name by joining the `profiles` table.
- Provides `createCertificate(form)`, `updateCertificate(id, form)`, `deleteCertificate(id)` — CRUD. All operations pass `mandator_id` from the active mandator. `deleteCertificate` prompts for confirmation at the view layer, not here.
- Provides `fetchCertificateSummary(mandatorId)` — calls the `get_certificate_summary` RPC and stores the result in `summary`. Returns fields: `total_count`, `expiring_soon_count`, `expired_count`. Used by the certificates list header banner and the future Dashboard.

### Composable — `useMandator` extension

Extend the existing `useMandator` composable with:

- A new reactive flag: `certificatesEnabled` (computed from `mandator.module_certificates`).
- Add `'certificates'` to the `enabledModules` computed list when the flag is active (already automatic via `MODULE_DEFINITIONS`, but called out here for completeness).
- Register the new module in the `MODULE_DEFINITIONS` array:
  ```ts
  { route: 'certificates', column: 'module_certificates', label: 'Certificates' }
  ```
- `isModuleEnabled('certificates')` returns the correct value.

### Navigation and routing

- In `App.vue`, the nav item for "Certificates" pointing to `/certificates` is rendered automatically by the existing `MODULE_DEFINITIONS` iteration — no manual nav entry is required.
- Add authenticated routes in `router/index.ts`:
  ```ts
  { path: '/certificates', name: 'certificates', component: CertificatesView, meta: { requiresAuth: true, module: 'certificates' } }
  { path: '/certificates/:id', name: 'certificates-detail', component: CertificateDetailView, meta: { requiresAuth: true, module: 'certificates' } }
  ```

### View — `CertificatesView.vue` (list)

The top-level page for the feature: a sortable list of all certificates for the active mandator.

- Header with:
  - Page title "Certificates".
  - Summary pills (driven by `summary`): "Total: N", "Expiring soon: N" (warning), "Expired: N" (error). Rendered via `SyvoraBadge`.
  - Primary action: "Add certificate" button (`SyvoraButton`) — opens a `SyvoraModal` with the create form.
- Table or card list (card on mobile, table on desktop) with columns:
  - Name (linked to `/certificates/:id`).
  - Expiration date (formatted locale short, e.g. `20 Apr 2027`).
  - Responsible (display name from `profiles`, fallback to email, fallback to "—").
  - Status badge: `success` "Valid" (>30 days), `warning` "Expiring" (≤30 days, ≥0 days), `error` "Expired" (<0 days).
- Empty-state (`SyvoraEmptyState`): "No certificates yet. Add one to start tracking renewal dates."
- "Add certificate" modal fields (minimal create form):
  - Name (`SyvoraInput`, required).
  - Expiration date (`SyvoraInput` type `date`, required).
  - Responsible person (dropdown of mandator members, optional).
  - "Add more details" link that, when clicked, navigates to the detail view after save for adding provider/cost/notes — alternatively, expand the modal inline. The detail view is always available for post-creation editing.

### View — `CertificateDetailView.vue` (edit + full details)

Full edit surface for a single certificate. All fields editable inline.

**Basics**:
- Name (required), Expiration date (required), Responsible person (dropdown of mandator members).
- "Save" button (`SyvoraButton`) persists changes; "Delete" button (variant `ghost`, with confirm) removes the certificate and routes back to `/certificates`.

**Additional details**:
- Provider (`SyvoraInput`).
- Cost (`SyvoraInput` type `number`, with `suffix` for currency label).
- Notes (`SyvoraTextarea`, max ~2000 chars, `showCount` enabled).

**Status panel**:
- Status badge (same logic as list view).
- "Days until expiration" or "Days overdue" derived from `expires_at`.
- Last updated timestamp with updater's display name.

Navigation: breadcrumb-style "← Back to certificates" link at the top; unsaved-changes warning is out of scope.

### Admin UI — mandator management extension

- In the mandator create/edit modal within `AdminView.vue`:
  - A "Certificates" checkbox is added automatically via `MODULE_DEFINITIONS` — no manual AdminView edit needed, the existing loop renders it.
- The mandator list view displays a "Certificates" badge (enabled/disabled) consistent with existing module badges — also automatic.

### Sensible defaults

- The migration sets `module_certificates = true` on all existing mandator records so the feature is available immediately without manual admin intervention.
- The registration push into `MODULE_DEFINITIONS` happens at application setup (e.g. in `main.ts` or a dedicated `src/modules/index.ts`) so the nav entry, admin toggle, and route guard all light up together.
- On certificate creation, `created_by` and `updated_by` are populated from the current session; `mandator_id` is sourced from the active mandator — the user never selects these manually.

## Definition of Done

- The `certificates` table exists with the specified schema, indexes, foreign keys, `set_updated_at` trigger, RLS policies scoped by mandator membership, and the `get_certificate_summary` helper function.
- The `mandators` table has `module_certificates` (BOOLEAN, default `true`).
- The `useCertificates` composable provides reactive state and CRUD operations plus a summary fetch backed by the RPC.
- The `useMandator` composable exposes `certificatesEnabled` and `'certificates'` is registered in `MODULE_DEFINITIONS`, so it appears automatically in `enabledModules`.
- A new "Certificates" tab appears in navigation when the module is enabled for the current mandator.
- Navigating to `/certificates` or `/certificates/:id` when the module is disabled redirects to the home view (existing router guard).
- The user can create a certificate with name, expiration date, and an optional responsible person from a modal on `/certificates`.
- The user can open `/certificates/:id` to edit full details (provider, cost, notes) and delete the certificate with confirmation.
- The list view shows status badges (Valid / Expiring / Expired) derived from `expires_at` and a summary header backed by `get_certificate_summary`.
- The admin can toggle the Certificates module per mandator via `AdminView.vue` (no manual AdminView code change required).
- All existing mandators are migrated with `module_certificates = true` (no breaking change on deploy).
- Toggling the module flag takes effect without a full page reload (via `refreshMandator()`).
- The `get_certificate_summary` RPC returns the same counts the upcoming Dashboard feature will consume — no schema change is expected when the Dashboard is built.
