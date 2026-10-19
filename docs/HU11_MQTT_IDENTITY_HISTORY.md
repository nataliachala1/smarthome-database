# HU11 — Historial técnico de registro y revocación

Fecha: 2026-10-15. Cuarto incremento en `11-dev`, sobre BD `ef84f7eac24ab7b3e83c2b13b92cfe940a315f4f` y backend `35ef316b7afb32102a2373163b967be7a81f0f5f`. Diff y resultados de pruebas presentados; commit/push de este incremento autorizados por el usuario el 2026-10-15.

## Cambio incremental

Se añade `releases/011_mqtt_identity_events/`, changeset `hu11-mqtt-identity-events-v1`, y su include al master. La base pasa de 63 a 64 changesets; no se editan migraciones históricas ni las funciones existentes de registro/revocación.

`devices.mqtt_identity_event` conserva ID secuencial, referencia a identidad, tipo de evento, estados anterior/resultante, intento, código estable de error y fecha. No hay secretos, leases, payloads ni JSON libre. El backend coordina el modelo Prisma y la auditoría de arranque; no usa `prisma db push`.

Un trigger AFTER captura `REGISTERED`, `REVOKE_REQUESTED`, `ATTEMPT_STARTED`, `RETRY_SCHEDULED` y `REVOKED` en la misma transacción que la identidad. Un rollback revierte ambos y una inserción fallida de historial aborta la operación original. Un reclamo no prueba envío al broker; finalizar conserva el contrato de ACK del trabajador, sin demostrar estado físico.

Para identidades anteriores se inserta únicamente `BASELINE_SNAPSHOT`: observación al migrar, sin simular fechas o eventos pasados. Se preservan todos sus campos, incluyendo estado, intentos y error. No se adoptan dispositivos sin identidad individual.

## Permisos y conservación

La tabla tiene RLS sin políticas directas; los roles de ejecución no reciben acceso de tabla/secuencia ni ejecución de funciones trigger. Un guard rechaza UPDATE/DELETE/TRUNCATE y la FK restringe borrar identidades referenciadas. No se altera `identity_audit.audit_log` ni se atribuyen actores humanos al historial técnico.

No es una protección contra un DBA capaz de cambiar DDL o deshabilitar triggers. La consulta del historial queda reservada a administración de BD autorizada; no hay endpoint nuevo. No se define purga ni retención automática.

La migración toma un bloqueo sobre el registro antes del snapshot y la instalación del trigger, dentro de la transacción de Liquibase. `lock_timeout=5s` limita la espera de bloqueos, no el tiempo total de backfill. El rollback bloquea ambas tablas y exige historial vacío: cualquier observación/evento causa `MQTT_IDENTITY_HISTORY_ROLLBACK_REQUIRES_EMPTY_HISTORY`.

## Coordinación operativa

`scripts/audit-mqtt-revocation.sql` devuelve ahora **nueve** filas. Todas deben tener `passed=true`, usando el LOGIN real del revocador sin `SET ROLE`. Se comprueban las dos funciones nuevas y la captura activa: tabla/RLS, triggers esperados, sin condiciones ni columnas que limiten su alcance, y modo de sesión `origin`.

Aplicar primero esta revisión BD y después el backend actualizado. El backend habilitado rechaza una BD anterior; durante operación suspende nuevos reclamos si falla la auditoría. La comprobación no impide que un administrador cambie privilegios después. La activación del trabajador sigue siendo explícita y no se cambió la configuración del proyecto.

## Evidencia

- 104 pruebas reales: 76 de persistencia/runtime y 28 con broker TLS, incluyendo 22 casos nuevos de historial. Se verifican permisos de seis LOGIN, eventos de reintento/éxito, rollbacks transaccionales, tokens obsoletos, captura activa y guard contra modificaciones.
- Liquibase desde cero; rollback vacío/reaplicación; upgrade 62 → 63 → 64 con checksums y datos anteriores intactos. Tres identidades preexistentes conservan sus estados y reciben snapshots explícitos. Rollback poblado rechazado sin pérdida de historial ni cambio de changelog.
- 255 unitarias del backend, compilación, TypeScript, ESLint afectado, sintaxis del harness y validación/generación Prisma aprobados.
- Contenedores y certificados propios retirados al terminar; material previo de HU13 preservado. Sin pruebas de carga o backfill a escala productiva.

Reproducir desde backend: `node scripts/test-mqtt-revocation.cjs ../hu11-database`. Solo usa PostgreSQL/Mosquitto nuevos desechables; PostgreSQL de prueba sin TLS y MQTT con TLS real. El reset privilegiado de las tablas entre casos existe únicamente en la fixture aislada, con restauración transaccional de su guard.

Quedan pendientes emisión/rotación, posesión/pairing, auditoría de actores, métricas, política de retención, integración HU13/HU16 y despliegue. No se modificaron `.env`, cuentas de despliegue, bases existentes ni Shelly físico.
