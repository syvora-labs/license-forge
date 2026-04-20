-- ============================================================
-- Admin RLS policies
-- Lets admins of a mandator manage it via the AdminView:
--   • toggle modules (UPDATE mandators)
--   • invite / promote / demote / remove members
--   • create additional mandators (creator becomes admin)
-- ============================================================

-- Helper: is the current user an admin of the given mandator?
CREATE OR REPLACE FUNCTION public.is_mandator_admin(p_mandator_id uuid)
RETURNS boolean AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.mandator_users
        WHERE mandator_id = p_mandator_id
          AND user_id = auth.uid()
          AND role = 'admin'
    );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ── profiles: loosen SELECT so admins can look up invitees ──

DROP POLICY IF EXISTS "Users can read own profile" ON public.profiles;

CREATE POLICY "Authenticated users can read profiles"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (true);

-- ── mandators: admin-scoped INSERT / UPDATE / DELETE ────────

CREATE POLICY "Authenticated users can create mandators"
    ON public.mandators FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Admins can update their mandator"
    ON public.mandators FOR UPDATE
    TO authenticated
    USING (public.is_mandator_admin(id));

CREATE POLICY "Admins can delete their mandator"
    ON public.mandators FOR DELETE
    TO authenticated
    USING (public.is_mandator_admin(id));

-- Auto-assign the creator as admin of the new mandator.
-- Solves the bootstrap problem: any user can create their first
-- mandator and become admin of it.
CREATE OR REPLACE FUNCTION public.handle_new_mandator()
RETURNS trigger AS $$
BEGIN
    IF auth.uid() IS NOT NULL THEN
        INSERT INTO public.mandator_users (mandator_id, user_id, role)
        VALUES (NEW.id, auth.uid(), 'admin');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_mandator_created ON public.mandators;

CREATE TRIGGER on_mandator_created
    AFTER INSERT ON public.mandators
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_mandator();

-- ── mandator_users: admins can fully manage memberships ─────

DROP POLICY IF EXISTS "Users can see own memberships" ON public.mandator_users;

CREATE POLICY "Users can see own memberships or admins can see their mandator's members"
    ON public.mandator_users FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid()
        OR public.is_mandator_admin(mandator_id)
    );

CREATE POLICY "Admins can invite members to their mandator"
    ON public.mandator_users FOR INSERT
    TO authenticated
    WITH CHECK (public.is_mandator_admin(mandator_id));

CREATE POLICY "Admins can update members in their mandator"
    ON public.mandator_users FOR UPDATE
    TO authenticated
    USING (public.is_mandator_admin(mandator_id));

CREATE POLICY "Admins can remove members from their mandator"
    ON public.mandator_users FOR DELETE
    TO authenticated
    USING (public.is_mandator_admin(mandator_id));
