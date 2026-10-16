# HU13 / BD-16 — Compatibilidad con validación RPC local

**Fecha:** 15/10/2026. **Rama:** `13-dev`, desde `09-dev` / `3e6e4b9`. Backend trabaja en `13-dev` desde `09-dev` / `6b033fe`. Incremento local pendiente de commit/push.

El backend valida resultados de MQTT.SetConfig, identificación y estado MQTT; clasifica errores HTTP/JSON/transporte y timeout; bloquea diagnóstico/provisioning LAN por defecto y en producción. La configuración de provisioning establece `ssl_ca=ca.pem`, porque Shelly documenta `null` como TCP plano. Debe comprobarse que el firmware confíe en la cadena del broker; las CAs privadas aún no tienen flujo de carga. La identificación agrega `mqttStatusErrorCode` sin persistirlo. [MQTT de Shelly](https://shelly-api-docs.shelly.cloud/gen2/ComponentsAndServices/Mqtt/).

## Impacto sobre BD

- No requiere columnas, tablas, índices, grants, policies ni cambios de Prisma.
- No agrega changesets ni modifica el master Liquibase.
- SetConfig inválido impide llegar a crear el dispositivo. No significa que se revierta el efecto físico de la llamada anterior.
- Se conservan autorización OWNER, unicidad de fabricante y baja lógica. Idempotencia/reconciliación de provisioning y revocación MQTT siguen en otros incrementos.
- La POC local utiliza las credenciales MQTT del backend; no emite una identidad individual por dispositivo y no satisface pairing productivo multiusuario.

## Evidencia y límites

Backend registra 93 pruebas unitarias y 62 casos sintéticos HTTP/RPC aprobados, más compilación, TypeScript y ESLint. La suite usa fixtures para JWT/RLS y persistencia: no aporta una nueva prueba de PostgreSQL, migraciones o permisos efectivos. No se conectó a una base instalada ni se intervino Shelly o broker.

BD `13-dev` parte de `09-dev`; no incluye los changesets posteriores de `16-dev`. El historial original de esta base no garantiza los objetos de sesión esperados por Prisma: revisar el puente HU09 `07de82f` y consumo HU16 `c23c7f3` al integrar, junto con backend HU16 `bc9d3ec`. Comparar además la historia instalada antes de migrar. Este incremento documental no solventa esa diferencia ni sustituye HU16.

## Integración propuesta

Un commit backend para el avance verificable BD-16 y otro documental de BD para registrar compatibilidad. Revisión del diff y resultados antes de commit/push, según la regla solicitada. No se mueve material entre ramas existentes ni se declara HU13 completa.
