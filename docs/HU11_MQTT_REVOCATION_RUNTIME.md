# HU11 — Auditoría y operación del trabajador de revocación

Este documento conserva la evidencia del tercer incremento. El [cuarto incremento](HU11_MQTT_IDENTITY_HISTORY.md) añade historial transaccional y amplía la auditoría de ocho a nueve comprobaciones.

Fecha: 2026-10-15. Tercer incremento en `11-dev`, sobre BD `eeef0824a445e64d77fefcfaf0c60ca2a26eeaf2` y backend `20eee233274bf8d89c479fdb44a2679e2a2d157a`. Diff y resultados de pruebas presentados; commit/push de este incremento autorizados por el usuario el 2026-10-15.

## Cambio de base de datos

Se añade `scripts/audit-mqtt-revocation.sql`, una consulta de catálogos de solo lectura. No modifica roles, grants, datos, esquema ni changelog. La copia de la consulta en backend se compara literalmente con este archivo en las pruebas coordinadas.

Ejecutarla usando el LOGIN real del revocador, sin `SET ROLE` y sin cuenta migradora. Debe devolver ocho filas con `passed=true`: login esperado, roles sin privilegios elevados, membresías aisladas, ausencia de propiedad de objetos/base, RLS del registro, seguridad/permisos de funciones administrativas, ausencia de privilegios directos de tabla/columna y ausencia de CREATE en esquemas de negocio.

El LOGIN solo debe heredar `smarthome_mqtt_revoke`. El script rechaza mezcla con API, ingesta, registrar o administración, incluso privilegios elevados ocultos tras `SET ROLE`. Comprueba funciones HU11 presentes, SECURITY DEFINER/search_path fijo y ausencia de EXECUTE a PUBLIC. Una propiedad de función nula no cuenta como válida. No es una certificación del código de las funciones ni de todos los privilegios del servidor.

## Coordinación con backend

El nuevo proveedor Nest está desactivado por defecto. Al habilitarlo utiliza `DATABASE_MQTT_REVOKE_URL` con el mismo host, puerto y nombre de BD que API/ingesta, con LOGIN diferente y sin parámetros URL. Producción exige TLS PostgreSQL verificado; `DATABASE_MQTT_REVOKE_CA_FILE` permite una CA propia.

El pool máximo es uno; conexión/consulta/statement tienen límite de 5 segundos y los locks de 3 segundos. La auditoría ocurre al arrancar y antes de reclamar cada tarea. El trabajador solo ejecuta las funciones existentes de reclamo/finalización; no recibe SELECT directo de tablas ni capacidad de registro. Si la auditoría falla inicialmente, falla el arranque habilitado. Si los permisos cambian durante operación, suspende reclamos hasta corregirlos.

Los intentos son seriales y cada tarea usa una conexión administrativa MQTT nueva, TLS, sin reconexión automática. La tarea SQL mantiene reintentos y lease. La baja no equivale a revocación aplicada; no se modifica esa semántica ni se envía OFF físico. El supervisor cierra la tarea en curso y luego el pool al cerrar el contexto Nest.

## Evidencia

- 82 pruebas reales de PostgreSQL/broker TLS: 54 de persistencia/runtime y 28 de broker. Las 14 nuevas incluyen grants indebidos por columna, ejecución PUBLIC, ausencia de search_path fijo, roles incorrectos y sesión privilegiada enmascarada; también operación automática, recuperación al reparar acceso al broker y suspensión/reanudación por cambios de roles.
- 255 unitarias y 31 pruebas sintéticas de namespace/TLS, compilación, TypeScript y ESLint del backend aprobados.
- Liquibase limpio, rollback vacío/reaplicación y upgrade 62 → 63, sin cambiar checksums previos ni el dispositivo existente de prueba. No hay changesets adicionales en este incremento.
- Cierre de contexto Nest deja cero conexiones PostgreSQL del trabajador. Contenedores/certificados propios de la prueba retirados al terminar.

Reproducir desde backend: `node scripts/test-mqtt-revocation.cjs ../hu11-database`. Se usan bases y broker nuevos desechables. PostgreSQL de la fixture no usa TLS; sus opciones TLS productivas se validaron en unitarias. El broker sí usa TLS real. No se probaron señales del sistema ni Shelly físico.

## Activación pendiente

La migración previa y este script no habilitan por sí solos el trabajador. Antes de activar en staging: provisionar LOGIN dedicado sin privilegios extra, exigir ocho comprobaciones válidas, configurar certificados y credenciales administrativas de broker y un client ID exclusivo por réplica. El backend usa `MQTT_REVOCATION_ENABLED=true` solo por decisión explícita de despliegue.

No se modificó `.env`, no se crearon cuentas de despliegue ni se consultó/modificó la base existente. No se registran identidades anteriores automáticamente. Quedan pendientes pairing/posesión, emisión/rotación y compensación, auditoría completa, métricas de pendientes y la integración del material HU13/HU16.
