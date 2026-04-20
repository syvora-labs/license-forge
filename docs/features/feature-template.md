# Feature: <Feature Name>

## Description

<One or two paragraphs describing what this feature does, who it's for, and how it fits into the wider system. Mention any module gating (e.g. `module_xyz`), any external systems it integrates with, and what is explicitly *out of scope* (e.g. handled by a separate project). Keep it high-level — implementation details belong in Deliverables.>

The module is gated behind the mandator profile system (`module_<name>`) and follows the same enable/disable pattern as all other ERP modules.

## Deliverables

### Database — `<table_name>` table

<One-line description of what this table stores.>

| Column | Type | Constraints |
| --- | --- | --- |
| `id` | UUID | PK, default `gen_random_uuid()` |
| `mandator_id` | UUID | NOT NULL, FK → `mandators(id)` |
| `<column>` | <TYPE> | <constraints> — <inline description> |
| `created_by` | UUID | FK → `auth.users(id)` |
| `updated_by` | UUID | FK → `auth.users(id)` |
| `created_at` | TIMESTAMPTZ | DEFAULT `now()` |
| `updated_at` | TIMESTAMPTZ | DEFAULT `now()`, with existing `set_updated_at` trigger |

RLS policies: <describe who can SELECT / INSERT / UPDATE / DELETE, typically scoped by `mandator_id`. Call out any exceptions such as service-role-only writes.>

<Repeat the table block for each additional table.>

### Database — `mandators` table extensions

Add the following columns to the existing `mandators` table:

| Column | Type | Constraints |
| --- | --- | --- |
| `module_<name>` | BOOLEAN | NOT NULL, DEFAULT `true` |
| `<extra_setting>` | <TYPE> | — <description, e.g. API key, webhook secret> |

Note: <any sensitivity notes — e.g. keys are admin-only, read by service role, etc.>

### Database — helper function: `<function_name>(<args>)`

<Describe what the function returns and where it's used.>

```sql
CREATE OR REPLACE FUNCTION <function_name>(<args>)
RETURNS <return_type> AS $$
  <body>
$$ LANGUAGE sql STABLE SECURITY DEFINER;
```

### Composable — `use<FeatureName>`

A new composable following the established pattern that:

- Exposes `<state1>` (ref array), `<state2>` (ref array), `loading` (ref boolean) state.
- Provides `fetch<Things>(<scopeId>)` — <what it fetches, ordering, any enrichment via RPCs or joins>.
- Provides `create<Thing>(form)`, `update<Thing>(id, form)`, `delete<Thing>(id)` — CRUD. <Note any preconditions on delete.>
- Provides `fetch<Summary>(<scopeId>)` — returns an aggregated summary: <fields>. Used for <where>.

### Composable — `useMandator` extension

Extend the existing `useMandator` composable with:

- A new reactive flag: `<name>Enabled` (computed from `mandator.module_<name>`).
- Add `'<name>'` to the `enabledModules` computed list when the flag is active.
- Register the new module in the `MODULE_DEFINITIONS` array:
  ```ts
  { route: '<name>', column: 'module_<name>', label: '<Label>' }
  ```
- `isModuleEnabled('<name>')` returns the correct value.

### Navigation and routing

- In `App.vue`, add a new nav item for "<Label>" pointing to `/<name>`, wrapped with `v-if="<name>Enabled"`.
- Add authenticated routes in `router/index.ts`:
  ```ts
  { path: '/<name>', name: '<name>', component: <Feature>View, meta: { requiresAuth: true, module: '<name>' } }
  { path: '/<name>/:<paramId>', name: '<name>-detail', component: <Feature>DetailView, meta: { requiresAuth: true, module: '<name>' } }
  ```

### View — `<Feature>View.vue` (<short purpose>)

<Describe the top-level view for this feature.>

- <List item: what's shown, columns, badges, counts.>
- <Primary action button and where it navigates.>
- <Empty-state behavior.>

### View — `<Feature>DetailView.vue` (<short purpose>)

<Describe the detail/config view.>

**<Section name>**:
- <What's listed, columns, inline actions.>
- <"Add" button opens a modal with fields: …>
- <Inline edit / delete rules, including any disabled conditions.>

**<Section name>**:
- <Tables, expandable rows, status badges, etc.>

**Summary panel**:
- <Aggregated stats displayed.>

### <Related feature> integration — `<Existing>View.vue` extension

When the <Name> module is enabled for the current mandator, each <entity> row/card gains:

- A "<Badge>" showing <derived info>.
- A "<Action>" button that navigates to `/<name>/:<id>`.

### Admin UI — mandator management extension

- In the mandator create/edit modal within `AdminView.vue`, add:
  - A "<Label>" checkbox alongside existing module toggles, mapping to `module_<name>`.
  - <Any additional inputs for the extra mandator columns, e.g. secret keys as masked password inputs.>
  - <Visibility rules, e.g. admin-only.>
- The mandator list view displays a "<Label>" badge (enabled/disabled) consistent with existing module badges.

### Sensible defaults

- The migration sets `module_<name> = true` on all existing mandator records so that the feature is available immediately without manual admin intervention.
- The default mandator form factory (`getDefaultForm()`) in `useMandator` includes `module_<name>: true`.

## Definition of Done

- The `<table_1>`, `<table_2>`, … tables exist with the specified schemas, RLS policies, foreign keys, and the `<helper_function>` helper function.
- The `mandators` table has `module_<name>` (BOOLEAN, default `true`)<, and any additional columns with their types>.
- The `use<FeatureName>` composable provides reactive state and operations for <summary of what it does>.
- The `useMandator` composable exposes `<name>Enabled` and includes `'<name>'` in `enabledModules` and `MODULE_DEFINITIONS`.
- A new "<Label>" tab appears in navigation when the module is enabled for the current mandator.
- Navigating to `/<name>` when the module is disabled redirects to the first available enabled module.
- The admin can <primary admin capability 1>.
- The admin can <primary admin capability 2>.
- The admin can toggle the <Name> module<and configure any extra credentials> per mandator via `AdminView.vue`.
- <Related views> show <derived info> and a "<Action>" quick action when the <Name> module is enabled.
- All existing mandators are migrated with `module_<name> = true` (no breaking change on deploy).
- Toggling the module flag takes effect without a full page reload (via `refreshMandator()`).
- <Any cross-project contract guarantees — e.g. schema supports external project use cases without further changes.>
