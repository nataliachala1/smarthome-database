-- ============================================================
-- INSERT — Device types
-- File: 02_dml/00_inserts/004_insert_device_types.sql
-- Description: Inserts the initial catalog of IoT device
--              types supported by the Smart Home system.
--              The catalog was later removed by
--              01_ddl/11_refactors/001_remove_device_type.sql.
-- Authors: Karen Daniela Holguín Cruz, Natalia Chala Chala,
--          Kevin Stiven López Amaya
-- Institution: SENA — Análisis y Desarrollo de Software
-- Training group (ficha): 3145555
-- Version: 1.0.0
-- Date: 2025
-- SRS reference: RF3.1
-- Dependencies: 01_ddl/03_tables/003_create_devices_tables.sql
-- ============================================================

INSERT INTO devices.device_type (id_device_type, name, description, icon, created_at, updated_at)
VALUES
  (gen_random_uuid(), 'Lámpara inteligente', 'Bombilla o lámpara con control remoto de encendido/apagado y consumo medible',        'lamp',      NOW(), NOW()),
  (gen_random_uuid(), 'Enchufe inteligente', 'Enchufe con monitoreo de consumo y control remoto',                                   'plug',      NOW(), NOW()),
  (gen_random_uuid(), 'Aire acondicionado',  'Sistema de climatización con control de temperatura y programación',                   'ac',        NOW(), NOW()),
  (gen_random_uuid(), 'Calentador de agua',  'Calentador eléctrico de agua con control de temperatura',                             'heater',    NOW(), NOW()),
  (gen_random_uuid(), 'Lavadora',            'Electrodoméstico de lavado con monitoreo de ciclos y consumo',                        'washer',    NOW(), NOW()),
  (gen_random_uuid(), 'Nevera',              'Refrigerador con monitoreo de consumo energético',                                    'fridge',    NOW(), NOW()),
  (gen_random_uuid(), 'Televisor',           'Televisor con control remoto y monitoreo de consumo',                                 'tv',        NOW(), NOW()),
  (gen_random_uuid(), 'Computador',          'Equipo de cómputo con monitoreo de consumo',                                          'computer',  NOW(), NOW()),
  (gen_random_uuid(), 'Horno microondas',    'Microondas con monitoreo de uso y consumo',                                           'microwave', NOW(), NOW()),
  (gen_random_uuid(), 'Sensor de consumo',   'Sensor genérico de medición de consumo eléctrico',                                    'sensor',    NOW(), NOW()),
  (gen_random_uuid(), 'Ventilador',          'Ventilador con control remoto y monitoreo de consumo',                                'fan',       NOW(), NOW()),
  (gen_random_uuid(), 'Cargador',            'Punto de carga para dispositivos móviles o vehículos eléctricos',                     'charger',   NOW(), NOW()),
  (gen_random_uuid(), 'Otro',               'Dispositivo genérico no clasificado en las categorías anteriores',                    'device',    NOW(), NOW())
ON CONFLICT (name) DO NOTHING;