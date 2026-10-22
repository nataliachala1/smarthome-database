-- ============================================================
-- ROLES PostgreSQL - Smart Home
-- ============================================================
-- Estos roles son tecnicos y son independientes de:
--
--   auth.role:
--     SYSTEM_ADMIN
--     USER
--
-- y de homes.home_member.role:
--     OWNER
--     MEMBER
--     GUEST
--
-- Ninguno de estos roles contiene credenciales.
-- Los usuarios LOGIN se provisionan fuera de las migraciones.
-- ============================================================


-- ============================================================
-- smarthome_admin
-- Administracion tecnica de base de datos.
-- Puede atravesar RLS para tareas administrativas.
-- Nunca debe utilizarse como conexion normal de NestJS.
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
-- smarthome_app
-- Rol principal utilizado por NestJS.
-- RLS siempre debe aplicarse.
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = 'smarthome_app'
  ) THEN
    CREATE ROLE smarthome_app;
  END IF;
END
$$;

DO $$
BEGIN
  -- A PostgreSQL cluster may already use this role as its bootstrap
  -- superuser (POSTGRES_USER). Preserve that account; production
  -- application connections must use a separate LOGIN member role.
  IF EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = 'smarthome_app'
      AND rolsuper
  ) THEN
    RAISE NOTICE 'Preserving pre-existing superuser smarthome_app; use a separate LOGIN role for the application.';
  ELSE
    ALTER ROLE smarthome_app
      NOLOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      INHERIT
      NOREPLICATION
      NOBYPASSRLS;
  END IF;
END
$$;

COMMENT ON ROLE smarthome_app IS
  'Rol tecnico utilizado por NestJS. Acceso limitado por GRANT y Row Level Security.';


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
-- Jobs controlados: agregaciones, mantenimiento de particiones
-- y tareas internas controladas.
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
