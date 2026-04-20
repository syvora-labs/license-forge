-- ============================================================
-- Scaffolding migration
-- Creates: profiles, mandators, mandator_users, helper
-- functions, triggers, storage bucket, and RLS policies.
-- ============================================================

-- ── Helper: set_updated_at trigger function ─────────────────

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ── Profiles ────────────────────────────────────────────────

CREATE TABLE public.profiles (
    id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email       TEXT NOT NULL,
    display_name TEXT,
    avatar_url  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER set_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

-- Auto-create a profile row on sign-up
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

-- ── Mandators ───────────────────────────────────────────────

CREATE TABLE public.mandators (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL UNIQUE,
    slug        TEXT NOT NULL UNIQUE,
    created_by  UUID REFERENCES auth.users(id),
    updated_by  UUID REFERENCES auth.users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER set_mandators_updated_at
    BEFORE UPDATE ON public.mandators
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.mandators ENABLE ROW LEVEL SECURITY;

-- ── Mandator Users ──────────────────────────────────────────

CREATE TABLE public.mandator_users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mandator_id UUID NOT NULL REFERENCES public.mandators(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role        TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (mandator_id, user_id)
);

ALTER TABLE public.mandator_users ENABLE ROW LEVEL SECURITY;

-- ── Helper: get_user_mandator_ids ───────────────────────────

CREATE OR REPLACE FUNCTION public.get_user_mandator_ids()
RETURNS SETOF uuid AS $$
    SELECT mandator_id
    FROM public.mandator_users
    WHERE user_id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ── RLS: mandators (depends on get_user_mandator_ids) ───────

CREATE POLICY "Members can read their mandators"
    ON public.mandators FOR SELECT
    USING (id IN (SELECT public.get_user_mandator_ids()));

-- INSERT / UPDATE / DELETE are service-role only (no policy = denied for anon/authenticated)

-- ── RLS: mandator_users ─────────────────────────────────────

CREATE POLICY "Users can see own memberships"
    ON public.mandator_users FOR SELECT
    USING (user_id = auth.uid());

-- INSERT / UPDATE / DELETE are service-role only

-- ── Storage: avatars bucket ─────────────────────────────────

INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Avatar images are publicly accessible"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'avatars');

CREATE POLICY "Users can upload their own avatar"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'avatars'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Users can update their own avatar"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'avatars'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Users can delete their own avatar"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'avatars'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

-- ── Realtime ────────────────────────────────────────────────

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
    ) THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END
$$;

ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
ALTER PUBLICATION supabase_realtime ADD TABLE public.mandators;
ALTER PUBLICATION supabase_realtime ADD TABLE public.mandator_users;
