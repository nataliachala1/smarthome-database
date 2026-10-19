# HU16 — Persistencia para sesiones de vinculación Shelly

La release `019_device_pairing_sessions` agrega sesiones temporales vinculadas al hogar y al `OWNER` iniciador. Guarda hashes de `requestId` y token de sesión, identidad reportada por Android, estado, expiración y el dispositivo resultante. No guarda contraseña Wi-Fi, credenciales MQTT ni tokens en claro.

La release aditiva `020_lan_pairing_method` amplía el método permitido para aceptar `LAN` además de `AP` y `BLE` (BLE sigue rechazado por backend hasta tener una POC). No edita ni vuelve a ejecutar el changeset `019`; el método `LAN` representa coordinación de un dispositivo ya unido a la Wi-Fi, con RPC local desde Android. La API pública del backend no debe intentar alcanzar IP privadas del teléfono.

La función `devices.fn_claim_pairing_identity` serializa reservas por identificador de fabricante y rechaza equipos ya registrados o reservados en otra sesión vigente. El índice único case-insensitive `uq_device_manufacturer_id_ci` protege también altas concurrentes que lleguen por el registro genérico. La release falla antes de crear objetos si encuentra identificadores existentes que solo difieren por mayúsculas/minúsculas; deben resolverse antes de aplicar el changeset.

RLS limita la lectura, creación y cambio de sesión al usuario iniciador mientras sea `OWNER` activo del hogar. El trigger impone transiciones de estado y prohíbe completar antes de `CONNECTED`, con referencia al dispositivo registrado de mismo hogar e identidad. `CONNECTED` debe ser establecido por un futuro componente confiable tras observar la autenticación individual en el broker; un reporte de Android no lo acredita. La integración que obtiene esa evidencia todavía no existe.

El rollback se niega si hay historial de pairing, para evitar borrar auditoría o sesiones completadas. La migración es aditiva y se incluyó como changeset nuevo posterior a `018_household_permissions`; no se editaron releases aplicadas.

El rollback de `020_lan_pairing_method` también se niega si ya existen sesiones `LAN`; en ese caso se conserva el método y se corrige hacia adelante. La release no migra ni reconcilia `dev` ni verifica el `DATABASECHANGELOG` de una instancia: la línea base del documento adjunto corresponde a otro branch/ambiente y debe diagnosticarse de forma independiente antes de aplicar Liquibase.

## Estado frente a requisitos del 18/10/2026

En esta rama `16-dev`, el `changelog-master.yaml` incluye las releases `009`, `016`, `018`, `019` y `020`; no incluye las releases `011_mqtt_revocation` / `011_mqtt_identity_events` citadas para `dev`, y el código SQL de esta rama no define `devices.mqtt_identity`. Se conserva el alcance solicitado de `16-dev`; no se copió ni fusionó el changelog de `dev`. Por ello todavía no existe en esta rama la identidad MQTT ligada al dispositivo ni la revocación HU11 necesaria para cerrar el ciclo.

No se dispone aquí de la copia aislada con 73 filas de `DATABASECHANGELOG` descrita por el documento, ni de la conexión a la base destino. No se ejecutó Liquibase, SQL ni respaldo en una instancia del proyecto. Antes de migrar el ambiente se debe inspeccionar su changelog y dependencias; la presencia de las releases en Git no demuestra que estén aplicadas.

Quedan abiertos los bloqueadores que dependen de broker/infraestructura: aprovisionamiento MQTT por dispositivo compatible con EMQX Serverless o proveedor alternativo aprobado, evidencia autenticada para `CONNECTED`, outbox/compensación durable, revocación efectiva, bootstrap seguro de configuración y prueba Android/Shelly real. Las sesiones `LAN` son coordinación de contrato, no POC LAN completada.

Este esquema habilita coordinación durable; no configura el Shelly por AP/LAN, no implementa Android/BLE, no emite credenciales individuales y no declara completado el pairing extremo a extremo. La conciliación de ramas `dev`/`16-dev` y la migración de cualquier base destino deben planearse según su `DATABASECHANGELOG`; no aplicar esta release a un ambiente sin validar dependencias y changesets ejecutados.
