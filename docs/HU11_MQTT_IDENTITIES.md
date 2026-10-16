# HU11 — Fixture de identidad MQTT y coordinación de persistencia

Este documento conserva el alcance del primer incremento. El [segundo incremento](HU11_MQTT_REVOCATION.md) añade el changeset de registro y revocación durable y describe sus nuevas pruebas y límites.

Fecha: 2026-10-15. Rama `11-dev` desde `10-dev` / `9b9742b6d8f344440145d5b233e33161f9ac1d56`. Backend coordinado: `11-dev`, commit [`a0d4158`](https://github.com/nataliachala1/smarthome-backend/commit/a0d41581c7bd2f2bdb9ac289deb5054991214ba7), base `10-dev` / `63f4bf56a203ddb514fb53e935dc5860944f2e0a`. La dependencia corresponde al namespace probado en HU10. Diff y resultados de pruebas presentados; commit/push autorizados por el usuario el 2026-10-15.

## Artefactos y evidencia

Se añade `tests/mqtt/mosquitto.conf`, fixture para un Mosquitto TLS desechable con Dynamic Security y acceso anónimo deshabilitado. El script `scripts/test-mqtt-identity.cjs` del backend la monta en solo lectura y prepara CA/clave/credenciales aleatorias; el estado del broker vive en tmpfs. No modifica `docker-compose.yml`, credenciales ni contenedores existentes.

La última ejecución aprobó 28 pruebas con Mosquitto real 2.0.22 y dos dispositivos simulados: TLS positivo/negativo, autenticación individual, aislamiento A/B de publicación y suscripción, aislamiento administrativo, rutas de respuesta por equipo, rotación, revocación de sesión abierta y rechazo de reconexión. También se comprobó MQTT 3.1.1 y ausencia de secretos emitidos en claro en el estado del broker. Las credenciales administrativas de la fixture tienen solo acceso a Dynamic Security; las del backend de negocio no administran el broker.

Backend aprobó además 195 pruebas unitarias, 31 pruebas sintéticas heredadas de HU10, compilación, TypeScript y validaciones estáticas. Las pruebas no usan PostgreSQL ni Shelly físico. Los contenedores y certificados temporales se retiraron al finalizar; la imagen oficial queda en caché.

## Alcance de base de datos

No se cambian tablas, Prisma, funciones RLS, índices, grants ni changesets Liquibase. No se ejecutó ninguna migración ni SQL contra la instalación actual. El UUID técnico de identidad y el usuario `device-<uuid>` del adaptador aún no tienen un registro persistente de negocio. El ID de fabricante sigue intacto; el prefijo MQTT no se concatena en `manufacturer_device_id`.

El adaptador interno no valida pertenencia al hogar ni posesión y todavía no está conectado a endpoints de alta/baja. La restricción global de fabricante de `devices.device` no reserva por sí sola una identidad de broker antes de la inserción del dispositivo. Por eso no se afirma que el flujo completo ya impida doble vinculación o reemisión concurrente.

El siguiente incremento de persistencia requiere diseño incremental coordinado con HU12: referencia de identidad del broker por dispositivo, unicidad de credencial vigente, estado/versionado para emisión/rotación/revocación, auditoría y estrategia de reconciliación. Guardar metadatos/referencia de verificador, nunca la contraseña en claro. Revisar permisos técnicos y RLS antes de habilitar operaciones; no conceder capacidad administrativa del broker al rol de ingestión.

Una revocación solicitada en BD no equivale a una revocación aplicada en el broker. La operación probada deshabilita la identidad y cierra sus conexiones, pero aún falta unirla con la baja lógica y comprobar históricos mediante tests PostgreSQL. Un timeout administrativo deja resultado incierto; no borrar filas/históricos ni marcar éxito para compensarlo. La recuperación en la misma casa requiere posesión; la transferencia entre hogares sigue fuera del MVP.

## Reproducción e integración

Desde el backend: `node scripts/test-mqtt-identity.cjs C:/ruta/al/smarthome-database`. Requiere la imagen local `eclipse-mosquitto:2.0.22`, Docker, OpenSSL y dependencias del backend; usar la revisión HU11 de ambos repositorios. El script crea un puerto loopback aleatorio y elimina exclusivamente su contenedor y directorio temporal. Esta fixture no debe incorporarse al Compose productivo.

HU11 no incorpora aún los cambios de HU16 (`07de82f`, `c23c7f3` BD y `bc9d3ec` backend) ni el trabajo pendiente de HU13; deben preservarse al integrar. El archivo previo `revision-dispositivos.txt` y las copias originales de HU13 permanecieron intactos.
