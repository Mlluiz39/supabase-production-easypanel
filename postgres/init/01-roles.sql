-- Supabase Roles — Created on first PostgreSQL initialization
-- These roles are required for GoTrue, PostgREST, Storage, and Realtime

-- ─── Core Supabase Roles ──────────────────────────────

-- Authenticator: NOINHERIT LOGIN role used by PostgREST to connect,
-- then switches to the actual role (anon/authenticated/service_role) via JWT
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator WITH LOGIN NOINHERIT PASSWORD NULL;
  END IF;
END
$$;

-- Anon: Unauthenticated public access
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon WITH NOLOGIN;
  END IF;
END
$$;

-- Authenticated: Default role for logged-in users
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated WITH NOLOGIN;
  END IF;
END
$$;

-- Service Role: Admin bypass role (bypasses RLS)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role WITH NOLOGIN BYPASSRLS;
  END IF;
END
$$;

-- ─── Application Roles ────────────────────────────────

-- GoTrue Auth admin
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    CREATE ROLE supabase_auth_admin WITH LOGIN CREATEROLE CREATEDB REPLICATION BYPASSRLS;
  END IF;
END
$$;

-- Storage admin
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'supabase_storage_admin') THEN
    CREATE ROLE supabase_storage_admin WITH LOGIN CREATEROLE CREATEDB REPLICATION BYPASSRLS;
  END IF;
END
$$;

-- Realtime admin
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'supabase_realtime_admin') THEN
    CREATE ROLE supabase_realtime_admin WITH LOGIN CREATEROLE REPLICATION BYPASSRLS;
  END IF;
END
$$;

-- ─── Permissions ──────────────────────────────────────

-- authenticator can switch to any of the auth roles
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role TO authenticator;

-- authenticated inherits from anon (anon permissions are baseline)
GRANT anon TO authenticated;

-- ─── Realtime ────────────────────────────────────────
-- Create the _realtime schema and configure it for logical replication
CREATE SCHEMA IF NOT EXISTS _realtime;
ALTER SCHEMA _realtime OWNER TO supabase_admin;
GRANT USAGE ON SCHEMA _realtime TO supabase_realtime_admin;

-- ─── Storage ─────────────────────────────────────────
-- Storage schema is created by the storage-api service on first boot
CREATE SCHEMA IF NOT EXISTS storage;
ALTER SCHEMA storage OWNER TO supabase_admin;
GRANT ALL ON SCHEMA storage TO supabase_storage_admin;
GRANT USAGE ON SCHEMA storage TO anon;
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT USAGE ON SCHEMA storage TO service_role;
