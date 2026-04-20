# Feature: Application Scaffolding

## Description

This feature establishes the foundational infrastructure required before any domain feature can be implemented. It covers Supabase client integration, authentication (sign-up, login, password reset, session persistence), the multi-tenant mandator system, the responsive application shell with navigation, profile management, route guards, and an admin panel for mandator configuration.

Everything in this spec is a prerequisite for feature modules. Once scaffolding is complete, any new feature can follow the standard feature template: add a migration, a composable, a nav entry, and views — the plumbing to support that workflow is provided here.

The frontend uses the `@syvora/ui` component library exclusively for all UI primitives (buttons, cards, modals, inputs, tabs, app shell, etc.). No additional CSS framework is introduced.

## Deliverables

### Dependency — `@supabase/supabase-js`

Add `@supabase/supabase-js` to the `web` workspace:

```bash
yarn workspace web add @supabase/supabase-js
```

### Environment — `.env` configuration

Add the following environment variables to `web/.env` (and `web/.env.example` as documentation):

| Variable | Description |
| --- | --- |
| `VITE_SUPABASE_URL` | Supabase API URL (e.g. `http://localhost:8000`) |
| `VITE_SUPABASE_ANON_KEY` | Supabase anonymous/public key |

### Database — `mandators` table

Stores tenant organisations. Every application entity is scoped to a mandator.

| Column | Type | Constraints |
| --- | --- | --- |
| `id` | UUID | PK, default `gen_random_uuid()` |
| `name` | TEXT | NOT NULL, UNIQUE |
| `slug` | TEXT | NOT NULL, UNIQUE — URL-safe identifier |
| `created_by` | UUID | FK → `auth.users(id)` |
| `updated_by` | UUID | FK → `auth.users(id)` |
| `created_at` | TIMESTAMPTZ | DEFAULT `now()` |
| `updated_at` | TIMESTAMPTZ | DEFAULT `now()` |

Trigger: `set_updated_at` — auto-updates `updated_at` on every UPDATE.

RLS policies:
- SELECT: authenticated users can read mandators they are members of (via `mandator_users`).
- INSERT: service role only.
- UPDATE: service role only.
- DELETE: service role only.

### Database — `mandator_users` join table

Maps users to mandators with a role. A user can belong to multiple mandators.

| Column | Type | Constraints |
| --- | --- | --- |
| `id` | UUID | PK, default `gen_random_uuid()` |
| `mandator_id` | UUID | NOT NULL, FK → `mandators(id)` ON DELETE CASCADE |
| `user_id` | UUID | NOT NULL, FK → `auth.users(id)` ON DELETE CASCADE |
| `role` | TEXT | NOT NULL, DEFAULT `'member'` — one of `'admin'`, `'member'` |
| `created_at` | TIMESTAMPTZ | DEFAULT `now()` |

Unique constraint on `(mandator_id, user_id)`.

RLS policies:
- SELECT: authenticated users can see rows where `user_id = auth.uid()`.
- INSERT / UPDATE / DELETE: service role only.

### Database — `profiles` table

Replaces the current dev-seed-only `profiles` table with a proper migration.

| Column | Type | Constraints |
| --- | --- | --- |
| `id` | UUID | PK, FK → `auth.users(id)` ON DELETE CASCADE |
| `email` | TEXT | NOT NULL |
| `display_name` | TEXT | |
| `avatar_url` | TEXT | |
| `created_at` | TIMESTAMPTZ | DEFAULT `now()` |
| `updated_at` | TIMESTAMPTZ | DEFAULT `now()`, with `set_updated_at` trigger |

RLS policies:
- SELECT: authenticated users can read their own profile (`auth.uid() = id`).
- UPDATE: authenticated users can update their own profile (`auth.uid() = id`).
- INSERT: triggered automatically via database function on auth sign-up (see below).

### Database — trigger function: `handle_new_user()`

Automatically creates a `profiles` row when a new user signs up via Supabase Auth.

```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
    INSERT INTO public.profiles (id, email)
    VALUES (NEW.id, NEW.email);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();
```

### Database — helper function: `set_updated_at()`

Shared trigger function reused by every table with an `updated_at` column.

```sql
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### Database — helper function: `get_user_mandator_ids()`

Returns the set of mandator IDs the current authenticated user belongs to. Used in RLS policies.

```sql
CREATE OR REPLACE FUNCTION public.get_user_mandator_ids()
RETURNS SETOF uuid AS $$
    SELECT mandator_id
    FROM public.mandator_users
    WHERE user_id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER;
```

### Database — storage bucket: `avatars`

Move the existing dev-seed avatar bucket into a proper migration:

- Bucket name: `avatars`, public: `true`.
- RLS SELECT: anyone can read (`bucket_id = 'avatars'`).
- RLS INSERT: authenticated users can upload to their own folder (`bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]`).
- RLS UPDATE: authenticated users can update files in their own folder (same condition).
- RLS DELETE: authenticated users can delete files in their own folder (same condition).

### Supabase client — `lib/supabase.ts`

Create `web/src/lib/supabase.ts`:

```ts
import { createClient } from '@supabase/supabase-js'

export const supabase = createClient(
    import.meta.env.VITE_SUPABASE_URL,
    import.meta.env.VITE_SUPABASE_ANON_KEY,
)
```

This is the single shared Supabase client instance used by all composables.

### Composable — `useAuth`

A new composable at `web/src/composables/useAuth.ts` that manages authentication state:

- Exposes `user` (ref, `User | null`), `session` (ref, `Session | null`), `loading` (ref boolean).
- Provides `signIn(email, password)` — email/password sign-in.
- Provides `signUp(email, password)` — creates a new account.
- Provides `signOut()` — ends the session and redirects to `/login`.
- Provides `resetPassword(email)` — sends a password reset email.
- Provides `updatePassword(newPassword)` — updates the password (for reset flow).
- Listens to `supabase.auth.onAuthStateChange` to keep `user` and `session` reactive.
- Initialises from `supabase.auth.getSession()` on first call.
- Singleton pattern: all components share the same reactive state.

### Composable — `useMandator`

A new composable at `web/src/composables/useMandator.ts` that manages mandator (tenant) state:

- Exposes `mandator` (ref, current mandator object or `null`), `mandators` (ref array of all mandators the user can access), `loading` (ref boolean).
- Provides `fetchMandators()` — queries the user's mandators via `mandator_users` join.
- Provides `selectMandator(id)` — sets the active mandator, persists choice to `localStorage`.
- Provides `refreshMandator()` — re-fetches the current mandator data (for real-time module flag updates without page reload).
- On init, restores the last-selected mandator from `localStorage`, falling back to the first available.
- Exposes `enabledModules` (computed string array) — derived from `module_*` boolean columns on the current mandator. Initially empty; feature modules register themselves here as they are built.
- Exposes `MODULE_DEFINITIONS` (reactive array):
  ```ts
  { route: string, column: string, label: string }[]
  ```
  Initially empty. Each feature module appends its definition during setup.
- Provides `isModuleEnabled(name: string)` — returns whether a given module is enabled for the current mandator.

### Composable — `useProfile`

A new composable at `web/src/composables/useProfile.ts`:

- Exposes `profile` (ref, profile object or `null`), `loading` (ref boolean).
- Provides `fetchProfile()` — fetches the current user's profile from the `profiles` table.
- Provides `updateProfile(fields)` — updates `display_name`, `avatar_url`.
- Provides `uploadAvatar(file)` — uploads to the `avatars` storage bucket, updates `avatar_url`.

### Navigation and routing

**Router (`web/src/router/index.ts`):**

Public routes (no auth required):
```ts
{ path: '/login', name: 'login', component: LoginView, meta: { requiresAuth: false } }
{ path: '/signup', name: 'signup', component: SignUpView, meta: { requiresAuth: false } }
{ path: '/reset-password', name: 'reset-password', component: ResetPasswordView, meta: { requiresAuth: false } }
{ path: '/update-password', name: 'update-password', component: UpdatePasswordView, meta: { requiresAuth: false } }
```

Protected routes (require auth):
```ts
{ path: '/', name: 'home', component: HomeView, meta: { requiresAuth: true } }
{ path: '/profile', name: 'profile', component: ProfileView, meta: { requiresAuth: true } }
{ path: '/admin', name: 'admin', component: AdminView, meta: { requiresAuth: true, requiredRole: 'admin' } }
```

**Navigation guard (`router.beforeEach`):**
- If route `requiresAuth` and no session → redirect to `/login`.
- If route is `/login` or `/signup` and user is already authenticated → redirect to `/`.
- If route has `meta.module` and that module is disabled for the current mandator → redirect to `/`.
- If route has `meta.requiredRole` and user does not have that role in the current mandator → redirect to `/`.

### App shell — `App.vue`

Wrap the entire application in the `AppShell` component from `@syvora/ui`:

- **`logo` slot**: Application name "License Forge" linking to `/`.
- **`nav` slot**: Navigation links rendered from a computed list. Each link is a `RouterLink`. The list includes:
  - "Home" → `/` (always visible when authenticated).
  - "Admin" → `/admin` (visible when user role is `admin` in current mandator).
  - Dynamic module entries: iterate `MODULE_DEFINITIONS` and render a link for each module where `isModuleEnabled(module.route)` is true.
- **`actions` slot**: 
  - Mandator switcher: a dropdown or `SyvoraCommandPalette` (triggered via `useHotkey('k')`) listing available mandators when the user belongs to more than one.
  - `SyvoraAvatar` showing the current user's avatar/name, clicking opens a dropdown with "Profile" and "Sign out" options.
- **`actions-mobile` slot**: Same actions adapted for mobile layout.
- When not authenticated (login/signup routes), render only the `RouterView` without the `AppShell`.

### View — `LoginView.vue` (sign in)

A centered card (`SyvoraCard`) containing:

- Email input (`SyvoraInput`).
- Password input (`SyvoraInput`, type password).
- "Sign in" button (`SyvoraButton`, primary). Shows loading state during sign-in.
- "Forgot password?" link → navigates to `/reset-password`.
- "Don't have an account? Sign up" link → navigates to `/signup`.
- `SyvoraAlert` (variant `error`) displayed on authentication failure.

### View — `SignUpView.vue` (registration)

A centered card containing:

- Email input.
- Password input.
- Confirm password input (client-side validation: must match).
- "Sign up" button. Shows loading state.
- "Already have an account? Sign in" link → navigates to `/login`.
- `SyvoraAlert` (variant `info`) shown after successful sign-up: "Check your email to confirm your account."
- `SyvoraAlert` (variant `error`) on failure.

### View — `ResetPasswordView.vue` (request password reset)

A centered card containing:

- Email input.
- "Send reset link" button.
- `SyvoraAlert` (variant `info`) on success: "Check your email for a reset link."
- "Back to sign in" link → `/login`.

### View — `UpdatePasswordView.vue` (set new password)

Shown when the user arrives from a password reset email link. Supabase passes the recovery token in the URL hash, which the auth client processes automatically.

- New password input.
- Confirm password input.
- "Update password" button.
- Redirects to `/` on success.

### View — `HomeView.vue` (dashboard landing)

Replace the current placeholder with an authenticated landing page:

- Greeting: "Welcome, {display_name or email}".
- List of enabled modules as `SyvoraCard` tiles, each linking to the module's route.
- `SyvoraEmptyState` if no modules are enabled: "No modules are enabled for this organisation. Contact your administrator."

### View — `ProfileView.vue` (user profile)

- `SyvoraAvatar` (editable) — clicking opens a file picker to upload a new avatar.
- `SyvoraFormField` + `SyvoraInput` for display name.
- `SyvoraFormField` + `SyvoraInput` for email (read-only, disabled).
- "Save" button (`SyvoraButton`).
- `SyvoraAlert` on success/error.

### View — `AdminView.vue` (mandator management)

Accessible only to users with `admin` role. Provides CRUD for mandators.

**Mandator list**:
- Table or card list of all mandators (fetched via service role or admin-scoped RPC).
- Each row shows: name, slug, member count, enabled module badges (`SyvoraBadge`).
- "Create mandator" button opens a `SyvoraModal`.

**Mandator create/edit modal**:
- `SyvoraFormField` + `SyvoraInput` for name.
- `SyvoraFormField` + `SyvoraInput` for slug (auto-generated from name, editable).
- Module toggles section: initially empty; as feature modules are built, each adds a checkbox here via `MODULE_DEFINITIONS`.
- "Save" / "Cancel" buttons in the modal footer.

**Mandator member management**:
- Within each mandator card/row, an expandable section or detail view listing members.
- Each member shows email, role (`SyvoraBadge`), and a role toggle (admin/member).
- "Invite user" button: input for email, role selector, sends an invite (or adds directly if user exists).
- "Remove member" action with confirmation.

### Migration file

Create a single SQL migration at `supabase/migrations/20260420000000_scaffolding.sql` that includes:

1. `set_updated_at()` trigger function.
2. `profiles` table with RLS and `handle_new_user()` trigger.
3. `mandators` table with RLS and `set_updated_at` trigger.
4. `mandator_users` join table with RLS.
5. `get_user_mandator_ids()` helper function.
6. `avatars` storage bucket with RLS policies.

The dev seed data (`infrastructure/docker/dev/data.sql`) should be updated to remove the now-redundant `profiles` table creation and avatar bucket setup, replacing them with seed mandators and test users if desired.

### Sensible defaults

- The migration creates no mandators by default — the first admin creates one via the admin panel.
- New users have no mandator membership until explicitly invited.
- The `profiles` row is auto-created on sign-up via trigger.
- `MODULE_DEFINITIONS` starts empty; each future feature module registers itself.

## Definition of Done

- The `@supabase/supabase-js` dependency is installed and the shared client at `lib/supabase.ts` is initialised from environment variables.
- The `profiles`, `mandators`, and `mandator_users` tables exist with the specified schemas, triggers, RLS policies, and the `handle_new_user`, `set_updated_at`, and `get_user_mandator_ids` helper functions.
- The `avatars` storage bucket exists with scoped RLS policies.
- The `useAuth` composable provides reactive session/user state, sign-in, sign-up, sign-out, and password reset.
- The `useMandator` composable provides reactive mandator state, mandator switching with localStorage persistence, `enabledModules`, `MODULE_DEFINITIONS`, and `isModuleEnabled()`.
- The `useProfile` composable provides profile fetch, update, and avatar upload.
- `App.vue` uses the `AppShell` component from `@syvora/ui` with logo, dynamic navigation, mandator switcher, and user avatar/menu.
- Navigation links are dynamically rendered based on auth state, user role, and enabled modules.
- The router has auth, public, and admin routes with `beforeEach` guards enforcing authentication, module access, and role requirements.
- `LoginView`, `SignUpView`, `ResetPasswordView`, and `UpdatePasswordView` are functional using `@syvora/ui` components.
- `HomeView` shows a personalised greeting and module tiles for enabled modules.
- `ProfileView` allows editing display name and uploading an avatar.
- `AdminView` allows admins to create/edit mandators, manage members, and toggle module flags.
- Unauthenticated users are redirected to `/login`; authenticated users on `/login` are redirected to `/`.
- The mandator switcher is available when a user belongs to multiple mandators and selection persists across sessions.
- Toggling a module flag on a mandator takes effect without a full page reload (via `refreshMandator()`).
- All UI is built exclusively with `@syvora/ui` components — no additional CSS framework or custom low-level styling.
