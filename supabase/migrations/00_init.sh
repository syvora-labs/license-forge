#!/bin/bash
# Runs once on fresh database initialization (skipped if data directory already exists).
# Fixes three issues with supabase/postgres:15.1.1.41 + newer service images:
#
# 1. Internal role passwords — the image creates supabase_auth_admin, supabase_admin,
#    authenticator, and supabase_storage_admin with no password or 'postgres', but the
#    service connection strings use $POSTGRES_PASSWORD. Set them to match.
#
# 2. _realtime schema — the realtime service sets search_path to _realtime immediately
#    on connect, before running its own migrations, so the schema must pre-exist.
#
# 3. auth function ownership — supabase/postgres pre-creates auth.uid(), auth.role(),
#    and auth.email() owned by postgres. GoTrue (supabase_auth_admin) needs to own
#    them to run its migration scripts.

set -e

psql -v ON_ERROR_STOP=1 --username postgres --dbname postgres <<-EOSQL

    -- 1. Sync internal role passwords with POSTGRES_PASSWORD
    ALTER USER supabase_auth_admin    WITH PASSWORD '${POSTGRES_PASSWORD}';
    ALTER USER supabase_admin         WITH PASSWORD '${POSTGRES_PASSWORD}';
    ALTER USER authenticator          WITH PASSWORD '${POSTGRES_PASSWORD}';
    ALTER USER supabase_storage_admin WITH PASSWORD '${POSTGRES_PASSWORD}';

    -- 2. Create _realtime schema
    CREATE SCHEMA IF NOT EXISTS _realtime;
    GRANT ALL ON SCHEMA _realtime TO supabase_admin;

    -- 3. Transfer auth schema and function ownership to supabase_auth_admin
    ALTER SCHEMA auth OWNER TO supabase_auth_admin;

EOSQL

# Transfer ownership of any auth functions created by the postgres image init scripts.
# Done in a second pass so the schema ownership above is committed first.
psql -v ON_ERROR_STOP=1 --username postgres --dbname postgres <<-'EOSQL'
    DO $$
    DECLARE
        r RECORD;
    BEGIN
        FOR r IN
            SELECT p.oid, p.proname,
                   pg_get_function_identity_arguments(p.oid) AS args
            FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'auth'
        LOOP
            EXECUTE format(
                'ALTER FUNCTION auth.%I(%s) OWNER TO supabase_auth_admin',
                r.proname, r.args
            );
        END LOOP;
    END $$;
EOSQL

echo "00_init.sh complete"
