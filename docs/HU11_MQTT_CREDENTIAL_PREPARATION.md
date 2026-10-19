# HU11 — Coordinación de preparación de credenciales MQTT

Fecha: 2026-10-15. Quinto incremento en `11-dev`, sobre BD `06b0eab4c05e99a04386157161d7879360e31985` y backend `b5221db267032d8dec1762208ea49ef72da28d2f`. Diff y resultados de pruebas presentados; commit/push de este incremento autorizados por el usuario el 2026-10-15.

## Alcance de este incremento

El backend añade dos operaciones internas al adaptador de Mosquitto: preparación de una contraseña final con el cliente observado deshabilitado e inspección estricta de su identidad/ACL. No hay endpoint, proveedor Nest de preparación ni alta integrada. Los métodos anteriores de creación y rotación conservan su capacidad de habilitar clientes; su coordinación transaccional con registro/baja sigue pendiente.

La preparación crea un cliente con contraseña temporal aleatoria que no devuelve, confirma su disable, instala otra contraseña y exige que la inspección final observe `DISABLED` y la política esperada. Mosquitto 2.0.22 no ofrece un flag de creación deshabilitada en `createClient`; son comandos separados. [Implementación oficial de clientes](https://github.com/eclipse-mosquitto/mosquitto/blob/v2.0.22/plugins/dynamic-security/clients.c).

La inspección verifica defaults denegados, rol/ACL exactos, username, client ID, un único rol y ausencia de grupos. Devuelve únicamente identidad esperada y estado observado; errores de política usan `MQTT_IDENTITY_POLICY_MISMATCH`. No obtiene secretos ni prueba posesión o pertenencia al hogar.

## Persistencia y límites

No se añade DDL ni se modifican migraciones aplicadas. Se mantienen **64 changesets**, el modelo Prisma, las funciones de registro/revocación, sus permisos y las nueve comprobaciones del trabajador. El historial documentado en [el cuarto incremento](HU11_MQTT_IDENTITY_HISTORY.md) continúa capturando exclusivamente las operaciones SQL existentes; no registra estas nuevas llamadas al broker.

`ENABLED`/`DISABLED` son observaciones administrativas del broker, no nuevos valores de `devices.mqtt_identity.state` ni estados de pairing. No se almacenan contraseñas temporales/finales, verificadores, payloads ni resultados de inspección en PostgreSQL.

Una respuesta de creación perdida puede dejar un cliente habilitado con secreto temporal no entregado; un fallo posterior puede dejarlo deshabilitado sin entregar el secreto final. Un duplicado se rechaza, sin adopción o reemisión automática. La inspección es una secuencia de lecturas, sin bloqueo contra otro administrador; no recupera secretos ni convierte un resultado incierto en éxito.

Antes del flujo de alta, backend y BD necesitan coordinar reserva previa a escritura en broker, autorización/posesión, entrega, compensación durable y activación/rotación serializada con revocación. La función de registro actual no reserva una identidad antes de emitirla. Invocarla después de `prepare` no garantiza atomicidad ni evita una baja concurrente. Esas operaciones y su historial requerirán un incremento propio; el contrato HU12 con móvil sigue pendiente.

## Evidencia coordinada

- Backend: **306 pruebas unitarias**, 13 suites; 51 casos nuevos. TypeScript, build Nest y ESLint afectado aprobados.
- **117 pruebas reales**: 76 de persistencia/runtime PostgreSQL y 41 de broker TLS; 13 casos nuevos de preparación/inspección. Se cubren credencial deshabilitada, activación exclusiva de prueba, respuestas perdidas, duplicados y política alterada.
- Liquibase desde cero, rollback vacío/reaplicación y actualización **62 → 63 → 64** aprobados. Checksums y datos anteriores preservados; snapshots de identidades previas y rechazo del rollback de historial poblado comprobados.
- Contenedores y certificados propios retirados al terminar. Patches previos de HU13 verificados por aplicación inversa en ambas copias originales; diff completo de este incremento exportado y verificado antes del commit.

Reproducir desde la copia de backend: `node scripts/test-mqtt-revocation.cjs ../hu11-database`. Usa únicamente PostgreSQL 16 y broker Mosquitto 2.0.22 nuevos desechables en loopback; SQL de prueba sin TLS y MQTT con TLS real. La pérdida de respuesta se simula después de aplicar la operación real. La activación de prueba solo comprueba contraseña/ACL y no expone un flujo de producto.

No se modificaron `.env`, base del proyecto, roles de despliegue, servicios existentes ni Shelly físico. El trabajador permanece desactivado por defecto. No hay certificación de producción, recuperación durable de preparación ni pairing físico; HU13/HU16 siguen pendientes de integración.
