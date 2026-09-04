-- ============================================================
-- RLS — Esquema sync
-- Archivo: 03_dcl/02_policies/006_rls_sync.sql
--
-- Tabla protegida:
--   sync.backup
--
-- sync.backup contiene únicamente metadata de respaldos.
-- Los backups/restauraciones reales pertenecen a
-- infraestructura/PostgreSQL.
--
-- Acceso funcional:
--   SYSTEM_ADMIN -> SELECT
--   USER         -> sin acceso
--
-- Escritura:
--   smarthome_admin mediante proceso técnico.
--
-- No existen policies INSERT/UPDATE/DELETE para smarthome_app.
-- ============================================================


-- ============================================================
-- sync.backup
-- ============================================================

ALTER TABLE sync.backup
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT — aplicación
--
-- smarthome_app es utilizado por distintos usuarios funcionales,
-- pero únicamente un usuario global SYSTEM_ADMIN puede consultar
-- la metadata de respaldos.
--
-- La policy no depende de id_user porque un SYSTEM_ADMIN debe
-- poder consultar todos los respaldos:
--
--   automaticos
--   manuales
--   completados
--   fallidos
--   en proceso
--
-- ------------------------------------------------------------

CREATE POLICY backup_system_admin_select_policy
ON sync.backup
FOR SELECT
TO smarthome_app
USING (
    auth.fn_is_system_admin()
);