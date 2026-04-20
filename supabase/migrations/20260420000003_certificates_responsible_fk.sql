-- ============================================================
-- Repoint certificates.responsible_user_id FK from auth.users
-- to public.profiles so PostgREST can embed the profile row
-- in select queries (e.g. select=*,responsible:responsible_user_id(...)).
-- profiles.id already cascades from auth.users, so the semantic
-- chain is preserved.
-- ============================================================

ALTER TABLE public.certificates
    DROP CONSTRAINT IF EXISTS certificates_responsible_user_id_fkey;

ALTER TABLE public.certificates
    ADD CONSTRAINT certificates_responsible_user_id_fkey
    FOREIGN KEY (responsible_user_id)
    REFERENCES public.profiles(id)
    ON DELETE SET NULL;

-- Nudge PostgREST to reload the schema cache
NOTIFY pgrst, 'reload schema';
