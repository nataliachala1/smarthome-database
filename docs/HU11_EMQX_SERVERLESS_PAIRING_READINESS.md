# HU11/HU12 — Coordinación pendiente con EMQX Serverless

Fecha: 2026-10-15. BD `11-dev`, base `a9589cac2f845f5135a64a49fd683b24b975555c`; backend `11-dev`, base `7730ff12fe1c86347f8c87adf02ea2d16e801825`. Incremento documental revisado y autorizado para commit/push el 2026-10-15. **Pairing y activación coordinada siguen abiertos.**

## Proveedor confirmado y alcance

El usuario confirmó EMQX Cloud Serverless para producción. La fixture y el administrador implementados anteriormente utilizan Mosquitto Dynamic Security. El backend ahora exige un proveedor administrativo explícito cuando se habilita el trabajador de revocación: admite `mosquitto-dynamic-security` y rechaza `emqx-serverless` con `MQTT_REVOCATION_PROVIDER_UNSUPPORTED` antes de abrir el pool o conectar el administrador. Sin proveedor tampoco arranca habilitado. Con el trabajador desactivado se mantiene el funcionamiento previo de la aplicación.

No basta con tener usuario/contraseña MQTT para administrar identidades. La API pública Serverless enumera operación de clientes conectados, suscripciones y publicación, pero no CRUD de credenciales/ACL; sus claves de API de acceso completo solo aplican a esas operaciones expuestas. El plan soporta autenticación por contraseña y X.509, pero no HTTP extended authentication/JWT ni autorización extendida contra PostgreSQL. La consola permite gestionar ACL manualmente y requiere regla deny-all para emular whitelist; eso no ofrece altas/bajas automatizadas por dispositivo. [API Serverless](https://docs.emqx.com/en/cloud/latest/api/serverless.html), [API por despliegue](https://docs.emqx.com/en/cloud/latest/api/api_deployment.html), [autenticación](https://docs.emqx.com/en/cloud/latest/deployments/auth_overview.html), [autorización](https://docs.emqx.com/en/cloud/latest/deployments/authz_overview.html), [ACL integrada](https://docs.emqx.com/en/cloud/latest/deployments/default_authz.html). Esta conclusión se limita al contrato público consultado el 2026-10-15; EMQX podría confirmar otro mecanismo soportado para la cuenta real. No se extrapola la API Dedicated ni se cambia el plan del usuario.

## Persistencia conservada

Este incremento no añade changesets ni modifica SQL, Prisma, permisos o estados. Se mantienen 64 changesets y las nueve comprobaciones de auditoría del trabajador. `devices.mqtt_identity` y su historial reflejan el ciclo existente; no prueban posesión física ni constituyen sesiones de pairing.

`fn_register_mqtt_identity` exige un dispositivo ya existente y activo. No es una reserva previa a emitir credenciales: llamar primero al broker y después al registro no da atomicidad. El revocador desactivado no procesa tareas pendientes; no se debe interpretar el estado SQL como revocación ya ejecutada en EMQX.

El cierre necesita evidencia de la POC BLE, contrato móvil/backend y administración real del broker. Solo después se definirán nuevos changesets para sesión temporal/reserva, consumo único, idempotencia, unicidad de fabricante y compensación durable. Es necesario serializar la activación con baja/cancelación/expiración y comprobar que comandos tardíos no reactivan identidades retiradas. No basta con leases SQL si el broker puede aplicar una habilitación retrasada.

Se conservan las decisiones del producto: vinculación solo OWNER, recuperación en el mismo hogar con evidencia, transferencia entre hogares bloqueada en el MVP, históricos de consumo conservados y ningún apagado físico automático al retirar un equipo. La contraseña Wi-Fi permanece fuera del backend y SecureStore.

## Móvil y validación

Referencia proporcionada: [`from_movil/dev`, `0dc85b0d0215ded9004c69881a095bb99461ebf5`](https://github.com/Kevin-Stiven-Lopez-Amaya404/from_movil/tree/0dc85b0d0215ded9004c69881a095bb99461ebf5). Su adaptador BLE sigue sin implementación nativa y `pairingService.createSession` devuelve `PAIRING_UNSUPPORTED`; los estados locales no son un contrato servidor validado.

Backend prepara los informes `docs/HU11_EMQX_SERVERLESS_PAIRING_READINESS.md` y `docs/HU12_SHELLY_ANDROID_BLE_POC.md`, con fuentes oficiales y pruebas de aceptación. Firmware y Android físico siguen pendientes de confirmar.

Evidencia final: **317 pruebas unitarias** del backend, TypeScript, compilación y ESLint afectados aprobados. **117 pruebas reales** aprobadas (76 PostgreSQL/runtime y 41 Mosquitto TLS). Migración desde cero, rollback vacío/reaplicación y actualización **62 → 63 → 64** aprobados; datos/checksums anteriores conservados y rollback de historial poblado rechazado. Las pruebas se ejecutan desde backend con `node scripts/test-mqtt-revocation.cjs ../hu11-database`, exclusivamente contra PostgreSQL y Mosquitto TLS desechables; ambos contenedores propios se retiraron al finalizar. No certifican EMQX ni pairing físico.

No se aplicó una migración a la base del proyecto, no se habilitó el trabajador en `.env` y no se modificaron credenciales de despliegue.
