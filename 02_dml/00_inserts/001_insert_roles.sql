-- ============================================================
-- INSERT — Roles del sistema
-- Archivo: 02_dml/00_inserts/001_insert_roles.sql
-- Descripción: Inserta los dos roles globales del sistema
--              definidos en el SRS (RF1.3). Estos roles
--              determinan el nivel de acceso de cada usuario.
-- Autor: Karen Daniela Holguín Cruz, Natalia Chala Chala,
--        Kevin Stiven López Amaya
-- Institución: SENA — Análisis y Desarrollo de Software
-- Ficha: 3145555
-- Versión: 1.0.0
-- Fecha: 2025
-- Referencia SRS: RF1.3
-- Dependencias: 01_ddl/03_tables/001_create_auth_tables.sql
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