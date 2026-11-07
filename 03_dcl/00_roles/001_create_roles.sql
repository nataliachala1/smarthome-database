-- ============================================================
-- PostgreSQL ROLES - Smart Home
-- ============================================================
-- These roles are technical and independent of:
--
--   auth.role:
--     SYSTEM_ADMIN
--     USER
--
-- and of homes.home_member.role:
--     OWNER
--     MEMBER
--     GUEST
--
-- None of these roles holds credentials.
-- LOGIN users are provisioned outside the migrations.
-- ============================================================


-- ============================================================
-- smarthome_admin
-- Technical database administration.
-- Can bypass RLS for administrative tasks.
-- Must never be used as the regular NestJS connection.
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = 'smarthome_admin'
  ) THEN
    CREATE ROLE smarthome_admin;
  END IF;
END
$$;

ALTER ROLE smarthome_admin
  NOLOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  INHERIT
  NOREPLICATION
  BYPASSRLS;

COMMENT ON ROLE smarthome_admin IS
  'Rol tecnico administrativo de Smart Home. NO debe utilizarse como conexion normal del backend.';


-- ============================================================
-- smarthome_runtime_app
-- Group role used by NestJS. It is kept separate from the
-- bootstrap user POSTGRES_USER, which may be a superuser.
-- RLS must always apply.
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = 'smarthome_runtime_app'
  ) THEN
    CREATE ROLE smarthome_runtime_app;
  END IF;
END
$$;

ALTER ROLE smarthome_runtime_app
  NOLOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  INHERIT
  NOREPLICATION
  NOBYPASSRLS;

COMMENT ON ROLE smarthome_runtime_app IS
  'Rol de grupo de NestJS. Nunca se usa como LOGIN ni como usuario bootstrap.';


-- ============================================================
-- smarthome_readonly
-- Consultas tecnicas/reportes autorizados.
-- No atraviesa RLS.
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = 'smarthome_readonly'
  ) THEN
    CREATE ROLE smarthome_readonly;
  END IF;
END
$$;

ALTER ROLE smarthome_readonly
  NOLOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  INHERIT
  NOREPLICATION
  NOBYPASSRLS;

COMMENT ON ROLE smarthome_readonly IS
  'Rol tecnico de solo lectura. Sus objetos permitidos se conceden explicitamente.';


-- ============================================================
-- smarthome_ingest
-- Ingesta MQTT / telemetria.
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = 'smarthome_ingest'
  ) THEN
    CREATE ROLE smarthome_ingest;
  END IF;
END
$$;

ALTER ROLE smarthome_ingest
  NOLOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  INHERIT
  NOREPLICATION
  NOBYPASSRLS;

COMMENT ON ROLE smarthome_ingest IS
  'Rol tecnico para ingesta MQTT y persistencia de telemetria.';


-- ============================================================
-- smarthome_worker
-- Controlled jobs: aggregations, partition maintenance
-- and controlled internal tasks.
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = 'smarthome_worker'
  ) THEN
    CREATE ROLE smarthome_worker;
  END IF;
END
$$;

ALTER ROLE smarthome_worker
  NOLOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  INHERIT
  NOREPLICATION
  NOBYPASSRLS;

COMMENT ON ROLE smarthome_worker IS
  'Rol tecnico para procesos programados y tareas internas controladas.';
