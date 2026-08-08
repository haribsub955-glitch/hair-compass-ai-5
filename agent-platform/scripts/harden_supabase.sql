-- Defence-in-depth for the Supabase move: make every table unreachable through the Data API.
--
-- These tables are created in `public`, which Supabase's Data API (PostgREST) exposes. This app
-- NEVER uses the Data API — it connects only as the database owner over the connection string — so
-- the correct posture is to deny the Data API entirely.
--
-- THREE layers, because RLS-with-no-policies alone is NOT enough:
--   1. Enable RLS on every current table in `public` — denies anon + authenticated via PostgREST.
--   2. REVOKE all privileges from the Data-API roles INCLUDING `service_role`. service_role has
--      BYPASSRLS, so a leaked service_role key would otherwise read every table through PostgREST
--      despite RLS. Layer 1 does nothing against it; this layer is what stops it.
--   3. ALTER DEFAULT PRIVILEGES so a table added LATER (a new @Model picked up by create_all) is
--      denied by construction, instead of silently inheriting Supabase's default grants until
--      someone remembers to re-run this — the "13th table leaks" trap.
-- The role this server connects as is unaffected by all three (it owns the tables and holds its
-- privileges directly), so the app keeps working unchanged. Verified on the Supabase Postgres image.
--
-- Idempotent. Run it after apply_schema.py. Role-guarded, so it no-ops cleanly if pointed at a plain
-- Postgres that has no Supabase roles.
--
-- STRONGEST step, and STRONGLY RECOMMENDED in addition: in the dashboard set
--   Settings -> API -> Exposed schemas  to EXCLUDE `public`.
-- That turns PostgREST off for the whole schema and does not depend on getting grants exactly right.

-- 1. RLS on every current base table in public (a loop, not a hardcoded list).
DO $$
DECLARE t text;
BEGIN
  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);
  END LOOP;
END $$;

-- 2 + 3. Deny the Data-API roles all access to current AND future objects in public.
-- Run this as the role the app connects as (the table owner). ALTER DEFAULT PRIVILEGES only affects
-- objects created BY the executing role — which is exactly the app's future tables. Run as any other
-- role and the default-privilege lines silently no-op on the entries that matter.
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      -- Tables are the data; sequences and functions are defence in depth — a future SQL function in
      -- public would otherwise be anon-callable via PostgREST /rpc, and sequences leak row counts.
      EXECUTE format('REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM %I;', r);
      EXECUTE format('REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM %I;', r);
      EXECUTE format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM %I;', r);
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES    FROM %I;', r);
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM %I;', r);
      EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM %I;', r);
    ELSE
      RAISE NOTICE 'harden_supabase: role % not present (not a Supabase project?) — skipping', r;
    END IF;
  END LOOP;
END $$;

-- Verify (for eyes): every table RLS-enabled, and no Data-API role holds table privileges.
SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;
SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND grantee IN ('anon', 'authenticated', 'service_role')
ORDER BY grantee, table_name;

-- Assert (for the deployment): fail with a non-zero psql exit if the hardening did not take. The
-- SELECTs above only print; a provisioning step needs an actual failure signal, not a report.
DO $$
DECLARE bad int;
BEGIN
  SELECT count(*) INTO bad FROM pg_tables WHERE schemaname = 'public' AND NOT rowsecurity;
  IF bad > 0 THEN
    RAISE EXCEPTION 'harden_supabase: % public table(s) still have RLS disabled', bad;
  END IF;
  SELECT count(*) INTO bad FROM information_schema.role_table_grants
   WHERE table_schema = 'public' AND grantee IN ('anon', 'authenticated', 'service_role');
  IF bad > 0 THEN
    RAISE EXCEPTION 'harden_supabase: % Data-API grant(s) still present on public tables', bad;
  END IF;
  RAISE NOTICE 'harden_supabase: OK — RLS on every public table, no anon/authenticated/service_role grants';
END $$;
