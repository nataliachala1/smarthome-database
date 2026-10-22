# HU09 / BD-03 — Puente del esquema de sesiones

**Fecha:** 14/10/2026. **Preparado en:** `16-dev`, como dependencia de las pruebas de permisos de consumo. **Changeset:** `hu09-session-schema-bridge-20261014`.

El ensayo del historial completo desde cero detectó que los 62 changesets originales no creaban `auth.refresh_token` ni `auth.user.session_version`. Prisma y las fixtures de HU09 sí los incluían. Por ello, la compatibilidad documentada en esos incrementos describía el contrato de código y sus fixtures, no la creación de esos objetos mediante Liquibase.

El [nuevo changeset](../releases/009_session_schema/changelog.yaml) se incluye después del DCL original. Agrega la columna de versión con valor inicial cero, la tabla de refresh, claves e índices de familia/usuario/hash y los permisos de columnas usados por el backend. `smarthome_runtime_app` recibe SELECT, INSERT de los campos necesarios y UPDATE de revocación/reemplazo/último uso; no recibe DELETE de refresh. Se habilita UPDATE de `session_version` y `updated_at` del usuario, que los casos de uso existentes necesitan.

Cuando existen objetos compatibles se conservan sus filas. Se comprueban tipos/nulabilidad de columnas y las claves primaria, única por hash y foránea sin cascadas. La comprobación no sustituye una comparación completa del esquema instalado y sus defaults, propietarios o políticas. Una divergencia detectada provoca error y rollback de la transacción Liquibase; no se reescribe ni reinicializa una tabla para resolverla.

**Rollback de compatibilidad:** es intencionalmente no destructivo. Conserva tabla, datos, columna y grants, aunque Liquibase retire el registro del changeset. No promete volver al esquema exacto anterior. La retirada física de esos objetos requiere un plan aparte y no forma parte de este incremento.

## Evidencia

Se aplicaron los 62 changesets originales y este puente sobre PostgreSQL 16 desechable con Liquibase 4.29.2. Después se aplicó el changeset de consumo de HU16 y se aprobaron 28 casos con LOGIN real no propietario, JWT, Prisma, RLS y Socket.IO. Se volvió a ejecutar el SQL del puente sobre el esquema ya existente y con refresh tokens sintéticos persistidos; la huella de esos tokens y lecturas permaneció igual.

La prueba utiliza un LOGIN que hereda `smarthome_runtime_app`, sin membresías en roles privilegiados o propietarios. No valida una instalación existente. La tabla de sesiones sigue siendo infraestructura de autenticación con permisos del rol de aplicación; no se presenta como una tabla de datos por hogar protegida por las nuevas políticas de consumo.

Ejecución desde backend `16-dev`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-consumption-access.ps1 -DatabaseRepository 'ruta-del-repositorio-BD'
```

Este comando crea sus servicios temporales y los elimina al finalizar; no llama al `docker-compose` de la instalación ni usa sus credenciales. El camino probado corresponde al historial versionado del ensayo. Antes de aplicar el puente sobre un snapshot o una base en uso, contrastar su `DATABASECHANGELOG`, checksums, esquema de sesiones y privilegios.

Backend probado: [bc9d3ec](https://github.com/nataliachala1/smarthome-backend/commit/bc9d3ec). [Reporte del incremento](https://github.com/nataliachala1/smarthome-backend/blob/bc9d3ec/docs/HU16_CONSUMPTION_ACCESS.md).
