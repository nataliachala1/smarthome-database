# HU11 — Registro y revocación durable en PostgreSQL

Fecha: 2026-10-15. Segundo incremento en `11-dev`, sobre `71443f27f38fc31ef08e29e8a0a60f40aad3f3db`; backend coordinado: commit [`20eee23`](https://github.com/nataliachala1/smarthome-backend/commit/20eee233274bf8d89c479fdb44a2679e2a2d157a), sobre `a0d41581c7bd2f2bdb9ac289deb5054991214ba7`. Diff y resultados de pruebas presentados; commit/push autorizados por el usuario el 2026-10-15.

## Cambio incremental

El master incluye al final `releases/011_mqtt_revocation/changelog.yaml`, un único changeset `hu11-mqtt-identity-durable-revocation-v1`. No se edita ningún changeset histórico ni se utiliza Prisma para modificar el esquema.

`devices.mqtt_identity` vincula un UUID v4 de broker con un dispositivo y su fabricante, ambos únicos. Conserva estado, timestamps, intentos, token/expiración del reclamo y un código de error permitido. No almacena secretos ni verificadores. El username se deriva como `device-<uuid>`. La FK impide borrar físicamente el dispositivo referenciado y el trigger impide cambiar fabricante/hogar de la identidad.

`REGISTERED` significa referencia registrada, no prueba de posesión ni confirmación de conectividad. El registro solo admite dispositivos MQTT activos de un hogar activo y fabricante coincidente; serializa con la baja bloqueando la misma fila. Repetir la referencia en estado REGISTERED es idempotente. No se puede sustituir ni volver a registrar una referencia REVOKE_PENDING/REVOKED. No se adopta automáticamente ningún dispositivo existente.

## Baja y trabajador

El trigger transforma REGISTERED en REVOKE_PENDING cuando `devices.device.deleted_at` pasa a no nulo. Todo sucede en la misma transacción que la baja; no realiza llamadas MQTT ni modifica históricos. La desactivación temporal sin `deleted_at` no dispara revocación. La autorización OWNER sigue siendo la de las políticas existentes del dispositivo.

`fn_claim_mqtt_revocation()` reclama una tarea mediante SKIP LOCKED, token nuevo y lease de 60 segundos. `fn_finish_mqtt_revocation(identity,token,error)` solo admite el reclamo vigente y no vencido. Error nulo confirma REVOKED tras ACK administrativo; un código permitido agenda reintento exponencial de 5 a 300 segundos. Una caída tras el ACK no pierde la tarea: vuelve a reclamarse al vencer el lease. Solo se reintenta deshabilitar; nunca habilitar o rotar.

La tabla tiene RLS sin acceso directo. PUBLIC, API, ingesta y roles generales no pueden ejecutar las funciones administrativas. Los nuevos NOLOGIN/NOBYPASSRLS `smarthome_mqtt_registrar` y `smarthome_mqtt_revoke` reciben solo registro y reclamo/finalización, respectivamente. Las funciones SECURITY DEFINER fijan search_path; no se crean cuentas LOGIN de despliegue ni se conceden membresías existentes.

## Evidencia reproducida

Desde el backend: `node scripts/test-mqtt-revocation.cjs ../hu11-database`. `tests/mqtt/hu10-baseline.yaml` reproduce la línea base publicada para probar actualización incremental.

- PostgreSQL 16 desechable y Liquibase 4.29: validación, migración limpia, rollback vacío/reaplicación, incremento 62 → 63 con checksums y dispositivo previo conservados.
- 40 pruebas de persistencia/coordinación más 28 de broker TLS: permisos de logins sin bypass, OWNER/MEMBER/GUEST/otro hogar, transacciones, concurrencia, recuperación y revocación real.
- Contenido de consumo, agregados, telemetría, alertas, notificaciones y auditoría conservado tras la baja y la revocación. Sin prueba de consulta de históricos por rol en este incremento: corresponde integrar HU16.
- Backend: 207 unitarias, compilación, TypeScript, ESLint y Prisma correctos.

El entorno de prueba usa credenciales efímeras, loopback, tmpfs y mounts de solo lectura. No lee `.env` ni utiliza servicios existentes. Contenedores y certificados retirados al finalizar; las imágenes quedan en caché.

## Despliegue y rollback

Solo se migraron bases desechables. El trabajador del backend requiere activación/configuración explícitas y todavía no tiene scheduler ni conexión productiva. Aplicar el changeset por sí solo no procesa revocaciones ni genera identidades para equipos anteriores.

El rollback aborta si existe cualquier referencia en el registro, para no perder revocaciones ni auditoría mínima. No se debe vaciar la tabla para forzarlo: usar corrección hacia adelante. Con registro vacío retira tabla, funciones y trigger, conservando los NOLOGIN por posibles membresías asignadas fuera de Liquibase.

Faltan reserva antes del alta, posesión, coordinación de emisión/rotación, compensación cuando un broker crea credenciales y falla su registro, auditoría completa y reconciliación operativa. Mantener la transferencia fuera del MVP y diseñar recuperación en la misma casa con posesión. No se prueba un Shelly físico ni se declara HU11 terminada.

Las ramas originales HU13 y el material HU16 permanecen intactos; deben integrarse sus changesets y correcciones de RLS antes de una entrega conjunta.
