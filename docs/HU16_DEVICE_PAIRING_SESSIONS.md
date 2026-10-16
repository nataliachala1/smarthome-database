# HU16 — Persistencia para sesiones de vinculación Shelly

La release `019_device_pairing_sessions` agrega sesiones temporales vinculadas al hogar y al `OWNER` iniciador. Guarda hashes de `requestId` y token de sesión, identidad reportada por Android, estado, expiración y el dispositivo resultante. No guarda contraseña Wi-Fi, credenciales MQTT ni tokens en claro.

La función `devices.fn_claim_pairing_identity` serializa reservas por identificador de fabricante y rechaza equipos ya registrados o reservados en otra sesión vigente. El índice único case-insensitive `uq_device_manufacturer_id_ci` protege también altas concurrentes que lleguen por el registro genérico. La release falla antes de crear objetos si encuentra identificadores existentes que solo difieren por mayúsculas/minúsculas; deben resolverse antes de aplicar el changeset.

RLS limita la lectura, creación y cambio de sesión al usuario iniciador mientras sea `OWNER` activo del hogar. El trigger impone transiciones de estado y prohíbe completar antes de `CONNECTED`, con referencia al dispositivo registrado de mismo hogar e identidad. `CONNECTED` debe ser establecido por un futuro componente confiable tras observar la autenticación individual en el broker; un reporte de Android no lo acredita. La integración que obtiene esa evidencia todavía no existe.

El rollback se niega si hay historial de pairing, para evitar borrar auditoría o sesiones completadas. La migración es aditiva y se incluyó como changeset nuevo posterior a `018_household_permissions`; no se editaron releases aplicadas.

Este esquema habilita coordinación durable; no configura el Shelly por AP, no implementa Android/BLE, no emite credenciales individuales y no declara completado el pairing extremo a extremo.
