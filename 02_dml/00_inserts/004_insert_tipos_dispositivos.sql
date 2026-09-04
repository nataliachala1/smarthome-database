-- ============================================================
-- INSERT — Tipos de dispositivos
-- Archivo: 02_dml/00_inserts/004_insert_tipos_dispositivos.sql
-- Descripción: Inserta el catálogo inicial de tipos de
--              dispositivos IoT compatibles con el sistema
--              Smart Home.
-- Autor: Karen Daniela Holguín Cruz, Natalia Chala Chala,
--        Kevin Stiven López Amaya
-- Institución: SENA — Análisis y Desarrollo de Software
-- Ficha: 3145555
-- Versión: 1.0.0
-- Fecha: 2025
-- Referencia SRS: RF3.1
-- Dependencias: 01_ddl/03_tables/003_create_devices_tables.sql
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