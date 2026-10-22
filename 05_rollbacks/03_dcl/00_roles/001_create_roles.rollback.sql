DROP ROLE IF EXISTS smarthome_worker;
DROP ROLE IF EXISTS smarthome_ingest;
DROP ROLE IF EXISTS smarthome_readonly;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = 'smarthome_app'
      AND rolsuper
  ) THEN
    RAISE NOTICE 'Preserving pre-existing superuser smarthome_app during rollback.';
  ELSE
    DROP ROLE IF EXISTS smarthome_app;
  END IF;
END
$$;
DROP ROLE IF EXISTS smarthome_admin;
