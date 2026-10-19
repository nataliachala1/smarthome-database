# HU10 — Compatibilidad de persistencia con MQTT TLS y namespace

Fecha: 2026-10-15. Rama `10-dev`, creada desde `09-dev` (`3e6e4b9f51df3e60eb00455c0e318277d1731df3`). Primer incremento coordinado con backend `10-dev`, base `6b033fe34775af269ba8138688a26f7f5f82e694`, implementado en el commit [`63f4bf56a203ddb514fb53e935dc5860944f2e0a`](https://github.com/nataliachala1/smarthome-backend/commit/63f4bf56a203ddb514fb53e935dc5860944f2e0a). Incremento revisado con diff y pruebas; commit y push autorizados por la responsable.

## Alcance de este incremento

Solo documentación. El backend incorpora opciones MQTT TLS verificadas y un contrato de tópicos derivado de `MQTT_TOPIC_NAMESPACE`. El namespace corresponde a una instalación/entorno, no a un permiso de hogar. El ID extraído sigue siendo `manufacturer_device_id` sin prefijo. La consulta de ingestión conserva los filtros `status = ACTIVE` y `deleted_at IS NULL`.

No se requieren tablas de tópicos ni cambios de identidad para este incremento. No se modifica Prisma, el índice único de fabricante, funciones de seguridad, RLS ni historial Liquibase. No se ejecutaron migraciones ni consultas sobre una instalación existente.

El prefijo por sí solo no impide que una identidad MQTT publique por otra. La autenticación/ACL individual y revocación requieren HU11 y un broker seleccionado. El cliente backend no debe compartir su credencial de servicio con Shelly; el provisioning LAN heredado queda bloqueado en backend al activar TLS o namespace hasta implementar bootstrap individual (HU11/HU12).

## Evidencia coordinada y límites

Backend pasó 155 pruebas unitarias, 31 de integración sintética de adaptadores, compilación, TypeScript y ESLint de los archivos cambiados. Las pruebas usan un repositorio simulado y no demuestran persistencia, privilegios PostgreSQL, RLS, migración limpia, ACL ni handshake TLS real. No se ejecutaron pruebas de BD en esta etapa porque no hay cambios SQL.

Esta rama parte de HU09 y no contiene los incrementos de HU16: `07de82f` (compatibilidad de sesiones) y `c23c7f3` (permisos de consumo e históricos). Esos cambios deben conservarse en la integración final junto con backend `bc9d3ec`. No se declara que esta rama aislada sea un esquema completo de producción.

El trabajo sin commit de HU13 y el archivo previo `revision-dispositivos.txt` permanecen intactos en la copia original. No se cambiaron ramas base, broker, credenciales reales, dispositivos ni infraestructura.
