-- ============================================================
-- Tighten the "expiring soon" threshold from 30 days to 7 days
-- for both certificates and licenses summary RPCs. The client
-- statusFor() helpers are updated in lockstep so the badge,
-- stat card, and summary counts all use the same cutoff.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_certificate_summary(p_mandator_id uuid)
RETURNS TABLE (
    total_count          INTEGER,
    expiring_soon_count  INTEGER,
    expired_count        INTEGER
) AS $$
    SELECT
        COUNT(*)::INTEGER AS total_count,
        COUNT(*) FILTER (
            WHERE expires_at >= current_date
              AND expires_at <= current_date + INTERVAL '7 days'
        )::INTEGER AS expiring_soon_count,
        COUNT(*) FILTER (WHERE expires_at < current_date)::INTEGER AS expired_count
    FROM public.certificates
    WHERE mandator_id = p_mandator_id;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

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
              AND expires_at <= current_date + INTERVAL '7 days'
        )::INTEGER AS expiring_soon_count,
        COUNT(*) FILTER (WHERE expires_at < current_date)::INTEGER AS expired_count
    FROM public.licenses
    WHERE mandator_id = p_mandator_id;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

NOTIFY pgrst, 'reload schema';
