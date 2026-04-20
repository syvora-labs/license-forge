-- ============================================================
-- Licenses feature
--   • mandators.module_licenses flag
--   • licenses table + indexes + RLS
--   • get_license_summary RPC
-- ============================================================

-- ── mandators: module flag ──────────────────────────────────

ALTER TABLE public.mandators
    ADD COLUMN module_licenses BOOLEAN NOT NULL DEFAULT true;

-- ── licenses table ──────────────────────────────────────────

CREATE TABLE public.licenses (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mandator_id          UUID NOT NULL REFERENCES public.mandators(id) ON DELETE CASCADE,
    name                 TEXT NOT NULL,
    expires_at           DATE NOT NULL,
    responsible_user_id  UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    provider             TEXT,
    cost                 NUMERIC(12, 2),
    notes                TEXT,
    created_by           UUID REFERENCES auth.users(id),
    updated_by           UUID REFERENCES auth.users(id),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_licenses_mandator_id ON public.licenses (mandator_id);
CREATE INDEX idx_licenses_expires_at  ON public.licenses (mandator_id, expires_at);

CREATE TRIGGER set_licenses_updated_at
    BEFORE UPDATE ON public.licenses
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- ── RLS: members of the mandator manage its licenses ────────

ALTER TABLE public.licenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can read licenses"
    ON public.licenses FOR SELECT
    TO authenticated
    USING (mandator_id IN (SELECT public.get_user_mandator_ids()));

CREATE POLICY "Members can insert licenses"
    ON public.licenses FOR INSERT
    TO authenticated
    WITH CHECK (mandator_id IN (SELECT public.get_user_mandator_ids()));

CREATE POLICY "Members can update licenses"
    ON public.licenses FOR UPDATE
    TO authenticated
    USING (mandator_id IN (SELECT public.get_user_mandator_ids()));

CREATE POLICY "Members can delete licenses"
    ON public.licenses FOR DELETE
    TO authenticated
    USING (mandator_id IN (SELECT public.get_user_mandator_ids()));

-- ── Summary RPC ─────────────────────────────────────────────

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

-- ── Realtime ────────────────────────────────────────────────

ALTER PUBLICATION supabase_realtime ADD TABLE public.licenses;

-- Nudge PostgREST to reload the schema cache so the responsible FK
-- embed resolves without a container restart.
NOTIFY pgrst, 'reload schema';
