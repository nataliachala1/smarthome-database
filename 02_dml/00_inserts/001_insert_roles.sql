-- ============================================================
-- INSERT — System roles
-- File: 02_dml/00_inserts/001_insert_roles.sql
-- Description: Inserts the two global system roles
--              defined in the SRS (RF1.3). These roles
--              determine each user's access level.
-- Authors: Karen Daniela Holguín Cruz, Natalia Chala Chala,
--          Kevin Stiven López Amaya
-- Institution: SENA — Análisis y Desarrollo de Software
-- Training group (ficha): 3145555
-- Version: 1.0.0
-- Date: 2025
-- SRS reference: RF1.3
-- Dependencies: 01_ddl/03_tables/001_create_auth_tables.sql
-- ============================================================

INSERT INTO auth.role (id_role, name, description, created_at)
VALUES
  (
    'a1b2c3d4-0001-0000-0000-000000000001',
    'SYSTEM_ADMIN',
    'Administrador técnico de la plataforma Smart Home.',
    NOW()
  ),
  (
    'a1b2c3d4-0001-0000-0000-000000000002',
    'USER',
    'Usuario registrado de Smart Home. Sus permisos dentro de cada hogar dependen de su membresía.',
    NOW()
  )
ON CONFLICT (name) DO NOTHING;