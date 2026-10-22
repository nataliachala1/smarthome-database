# HU16 / BD-04 y BD-05 — Consumo por rol e históricos

**Fecha:** 14/10/2026. **Rama:** `16-dev`. **Backend compatible:** [bc9d3ec](https://github.com/nataliachala1/smarthome-backend/commit/bc9d3ec). **Dependencia BD:** puente de sesiones `07de82f`.

La responsable aprobó que GUEST consulte únicamente el total de energía del hogar y el período solicitado. Este incremento restringe el acceso directo a lecturas y métricas a OWNER/MEMBER y expone un agregado básico autorizado, sin detalle de dispositivos. OWNER/MEMBER conservan históricos después de desactivar o retirar un dispositivo.

## Cambios incrementales

El changeset [hu16-consumption-detail-access-20261014](../releases/016_consumption_access/changelog.yaml) se incluye al final del master y no modifica los SQL de changesets anteriores.

| Objeto | Contrato |
|---|---|
| `consumption.fn_can_read_detail(UUID)` | OWNER activo de membresía, o MEMBER activo de hogar operativo. Reutiliza las comprobaciones existentes de usuario activo. |
| `consumption.fn_history_devices(UUID,UUID[])` | Metadata limitada de dispositivos solicitados del hogar autorizado: ID, nombre y fabricante, incluso tras baja. |
| `consumption.fn_basic_home_consumption(UUID,TIMESTAMPTZ,TIMESTAMPTZ)` | Total de energía para una membresía OWNER/MEMBER/GUEST activa en hogar operativo y rango válido. Sin autorización no devuelve fila; sin lecturas devuelve cero. |
| `consumption_app_select_policy` | Lecturas detalladas sujetas a `fn_can_read_detail`. |
| `consumption_metric_app_select_policy` | Misma restricción para métricas. |

Las funciones SECURITY DEFINER fijan `search_path`, usan esquemas explícitos y revocan EXECUTE a PUBLIC; solo se concede al rol de aplicación. No se amplían las políticas de dispositivos, las de ingesta ni los permisos de control. La visibilidad histórica de metadata se limita al helper autorizado, sin conceder SELECT general sobre dispositivos inactivos a MEMBER.

Se conserva la excepción histórica anterior para OWNER de un hogar inactivo; MEMBER y GUEST no acceden a ese hogar. Este cambio no crea un flujo de desactivación de hogares.

## Pruebas con el historial real

El script de backend `scripts/test-consumption-access.ps1` crea un PostgreSQL 16 nuevo con red Docker dedicada, datos en memoria y puerto aleatorio solo en loopback. Aplica con Liquibase 4.29.2 los 62 changesets originales y el [puente de sesiones](HU09_SESSION_SCHEMA_BRIDGE.md), excluyendo HU16; después aplica consumo de forma incremental. Total final: **64 changesets**.

La [fixture de consumo](../scripts/consumption-access-fixture.sql) carga únicamente datos sintéticos en `smarthome_consumption_test` y crea un LOGIN separado que hereda `smarthome_runtime_app`. Ese LOGIN carece de superusuario, BYPASSRLS, membresías elevadas y pertenencia a propietarios de tablas; la suite comprueba estas condiciones.

Resultado: **28 casos aprobados** con HTTP, JWT firmado, Prisma, políticas RLS y Socket.IO reales. Se cubren OWNER/MEMBER/GUEST, pendientes/revocados/terminados, ajenos, cuenta inactiva, creador sin membresía, dispositivo cruzado, históricos retirados, datos W/kWh conocidos y aislamiento al reutilizar una única conexión física. Los accesos SQL directos prueban lecturas, métricas y metadata, incluidos casos positivos. La suite comprueba que PUBLIC no pueda ejecutar los helpers y que una revocación confirmada quite detalle HTTP y realtime.

No se sustituyen guard JWT, repositorios de usuario/refresh, RLS o autorización realtime. Se emiten JWT de prueba para usuarios sintéticos; esta suite no prueba contraseñas, Argon2, broker, Shelly ni clientes finales.

Después de las pruebas se ejecuta de nuevo el SQL del puente sobre objetos preexistentes compatibles y se verifica la conservación de la huella de lecturas/refresh. Se ejecutan `rollback-count=1` de consumo y posterior `update`, comprobando de nuevo esa huella. El rollback de consumo **restaura el acceso detallado de GUEST del contrato anterior**; es un retroceso de seguridad y no debe aplicarse como una corrección aislada. El rollback del puente de sesiones conserva sus objetos, datos y grants intencionalmente.

## Ejecución e integración

Desde backend `16-dev`, con Docker, dependencias y cliente Prisma disponibles:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-consumption-access.ps1 -DatabaseRepository 'ruta-del-repositorio-BD'
```

El script no utiliza el compose de la instalación ni sus credenciales. Elimina únicamente la red y contenedores nuevos que crea y restaura la variable de conexión de prueba. `-MigrationOnly` omite la fixture y los 28 casos; Jest también los omite si falta `CONSUMPTION_TEST_DATABASE_URL`.

El backend nuevo requiere las funciones del changeset y debe integrarse con esta versión BD. Antes de actuar sobre una instalación real, comparar historial/checksums, objetos existentes y propietarios de funciones. La prueba desde cero no demuestra equivalencia con el antiguo snapshot o una base ya poblada.

BD-03/BD-04/BD-05 conservan trabajo pendiente fuera de este conjunto: instalación real, otras operaciones de permisos/control, clientes, duplicidad/reinicio/orden de telemetría y carga. BD-17 conserva WSS y coordinación entre réplicas. No hubo migración sobre bases en uso ni intervención en broker o Shelly.

[Contrato HTTP, resumen GUEST y reporte completo](https://github.com/nataliachala1/smarthome-backend/blob/bc9d3ec/docs/HU16_CONSUMPTION_ACCESS.md).
