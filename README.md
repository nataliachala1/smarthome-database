# Smart Home Database

HU14: [observabilidad del backend](docs/HU14_OBSERVABILITY_METRICS.md). Incremento sin DDL ni consultas persistidas; la salud y metricas se exportan desde NestJS.


HU16: [permisos de consumo, resumen GUEST aprobado e históricos](docs/HU16_CONSUMPTION_ACCESS.md). Incluye el [puente del esquema de sesiones faltante en el historial original](docs/HU09_SESSION_SCHEMA_BRIDGE.md). Los nuevos changesets se probaron solo en PostgreSQL desechable; contrastar la instalación antes de migrar.

HU16: [permisos de hogar y excepciones por dispositivo](docs/HU16_PERMISOS_HOGAR.md), release Liquibase `018_household_permissions`.

HU16: [sesiones de vinculación Shelly](docs/HU16_DEVICE_PAIRING_SESSIONS.md), release Liquibase `019_device_pairing_sessions`. El esquema reserva la identidad y protege la transición; la prueba confiable MQTT y el aprovisionamiento individual del broker siguen pendientes.

HU16 LAN: la release Liquibase `020_lan_pairing_method` agrega `LAN` como método de sesión; no habilita BLE ni cambia sesiones `AP` existentes. El alta sigue bloqueada hasta integrar proveedor MQTT individual y evidencia confiable.

Roles y permisos: [OWNER, MEMBER y GUEST](docs/ROLES_Y_PERMISOS.md). Las membresías MEMBER/GUEST tienen valores base por rol; `OWNER` puede ajustar permisos de hogar y dispositivo.

HU11/HU12: [EMQX Serverless y condiciones de activación coordinada](docs/HU11_EMQX_SERVERLESS_PAIRING_READINESS.md). El backend exige proveedor administrativo explícito; el trabajador Mosquitto no admite EMQX Serverless. Incremento documental sin DDL; pairing y activación siguen abiertos.

HU11: [coordinación de preparación de credenciales MQTT](docs/HU11_MQTT_CREDENTIAL_PREPARATION.md), sobre el [historial transaccional](docs/HU11_MQTT_IDENTITY_HISTORY.md), la [auditoría del trabajador](docs/HU11_MQTT_REVOCATION_RUNTIME.md), el [registro persistente](docs/HU11_MQTT_REVOCATION.md) y la [fixture TLS](docs/HU11_MQTT_IDENTITIES.md). Preparación interna sin DDL nuevo; reserva, activación coordinada, pairing y despliegue pendientes.

HU10: [compatibilidad de MQTT TLS y namespace con persistencia](docs/HU10_MQTT_TLS_NAMESPACE.md). Incremento documental sin DDL; identidad del broker y pairing siguen pendientes.


HU 09-dev: [baseline coordinado, auditoría de roles de solo lectura y pruebas aisladas](docs/HU09_SEGURIDAD_RUNTIME.md). No modifica el historial Liquibase ni autoriza reinicializar una base existente.

Cuarto incremento HU09: [familias de sesión y pruebas con PostgreSQL desechable](docs/HU09_SESSION_FAMILIES.md). La fixture no forma parte de las migraciones.

Alcance del 8 de septiembre: [migración a dispositivos por hogar, validaciones y pendientes](./VALIDACION_FINAL.md). El historial anterior se conserva y la nueva migración aún no se ha aplicado a la base local original.

Baseline PostgreSQL + Liquibase para Smart Home.

## Componentes activos

- `01_ddl`: extensiones, esquemas, tablas, integridad, funciones técnicas, triggers de `updated_at` e índices.
- `02_dml`: catálogos determinísticos mínimos (`SYSTEM_ADMIN`, `USER`) y tipos iniciales de dispositivo.
- `03_dcl`: roles técnicos PostgreSQL, privilegios mínimos y Row Level Security.
- `04_tcl`: sin scripts de negocio. Las transacciones funcionales pertenecen a NestJS + Prisma.
- `05_rollbacks`: rollback de todos los changeSets activos.

El contrato `devices.device` coincide con Prisma: cada dispositivo pertenece a un hogar, registra `last_seen_at` para el watchdog MQTT y permite desactivación temporal (`DEACTIVATED` con `deleted_at` nulo) además de eliminación lógica (`DEACTIVATED` con `deleted_at` informado).

Las views, materialized views y procedures heredadas fueron retiradas del baseline porque pertenecían al modelo anterior o duplicaban lógica de negocio.

## Inicio local

> El baseline parte de una base PostgreSQL limpia y no incluye zonas, tarifas eléctricas ni recomendaciones. Solo contempla la estructura vigente de hogar → dispositivo y los módulos activos de la fase 01-dev.

1. Copiar `.env.example` a `.env` y cambiar `POSTGRES_PASSWORD`.
2. No borres ni recrees volúmenes existentes. Si necesitas una base vacía, usa un proyecto/volumen de prueba separado.
3. Ejecutar `docker compose up -d --wait postgres`.
4. Validar: `docker compose run --rm liquibase --defaults-file=liquibase.properties validate`.
5. Revisar SQL: `docker compose run --rm liquibase --defaults-file=liquibase.properties update-sql`.
6. Aplicar: `docker compose run --rm liquibase --defaults-file=liquibase.properties update`.

> `smarthome_owner` es el usuario bootstrap/migrador del entorno local. Los roles `smarthome_runtime_app`, `smarthome_ingest`, `smarthome_worker`, `smarthome_readonly` y `smarthome_admin` son roles PostgreSQL `NOLOGIN`; las cuentas LOGIN y sus membresías se provisionan fuera de estas migraciones.

## Contexto RLS desde Prisma

La conexión funcional debe usar un LOGIN miembro de `smarthome_runtime_app`. Cada transacción de aplicación debe establecer el usuario funcional solo para esa transacción:

```sql
SELECT set_config('app.current_user_id', '<uuid>', true);
```

No utilizar un `SET` persistente sobre conexiones del pool.

## Despliegue Hostinger/Dokploy

El despliegue de `dev` se prepara en [docs/deployment](docs/deployment/ARCHITECTURE.md).
La composición de producción está en `docker-compose.production.yml`; no publica
PostgreSQL y aplica Liquibase antes de arrancar el backend. Revisa primero las
condiciones de acceso y el estado de la base existente en la documentación.
