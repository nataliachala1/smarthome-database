# HU09 / BD-17 — Familias de sesión y prueba PostgreSQL

**Fecha:** 14/10/2026. **Rama:** `09-dev`. **Backend compatible:** [6b033fe](https://github.com/nataliachala1/smarthome-backend/commit/6b033fe).

El backend vincula sus access tokens al `family_id` existente mediante el claim `sid`. Logout individual revoca la familia; HTTP y Socket.IO exigen que exista un refresh no revocado ni expirado de esa familia, usuario y `session_version`. Otro login del mismo usuario mantiene una familia independiente.

El esquema funcional sigue siendo el del commit `f097a0a`. Este incremento añade una fixture sintética y documentación, sin cambios en Liquibase, tablas, índices o permisos instalados.

## Contrato de persistencia

- Se reutilizan las columnas de `auth.refresh_token`: `id_refresh_token`, `id_user`, `token_hash`, `family_id`, `session_version`, `expires_at`, `revoked_at`, `replaced_by_token_hash`, `created_at` y `last_used_at`.
- `hasActiveFamily` filtra familia, usuario, versión, ausencia de revocación y expiración futura. Reutiliza el índice existente por familia; no se propone un índice nuevo sin medición.
- La rotación comprueba el predecesor y confirma creación del sucesor, revocación del anterior y uso en una transacción.
- Rotación y revocación adquieren el mismo `pg_advisory_xact_lock(hashtextextended(family_id::text, 0))` con aislamiento explícito `ReadCommitted`. Si logout confirma antes, no se puede crear un sucesor desde ese predecesor. Si confirma después, incluye al sucesor.
- El lock es transaccional, no un lock de sesión conservado en el pool. Las versiones que omitan este protocolo no deben mezclarse con el backend nuevo.

El LOGIN operativo deberá poder ejecutar esas operaciones sobre refresh tokens y adquirir el lock. Las pruebas siguientes no certifican los permisos de una instalación real. La revocación de todos los logins conserva la versión global del usuario.

## Fixture y ejecución

[scripts/session-security-fixture.sql](../scripts/session-security-fixture.sql) exige `smarthome_session_test`, crea `auth.user` con solo su clave y una tabla de refresh con las columnas necesarias. Es un subconjunto sintético, sin las políticas RLS, roles ni restricciones completas del sistema. No está incluido en ningún changelog y no debe usarse como migración o reemplazo del esquema real.

El script de backend [test-session-security.ps1](https://github.com/nataliachala1/smarthome-backend/blob/6b033fe/scripts/test-session-security.ps1) crea un PostgreSQL 16 nuevo con datos en memoria, contraseña sintética y puerto aleatorio solo en loopback. Monta la fixture de solo lectura, la ejecuta únicamente en ese servidor y elimina su contenedor al finalizar. No usa ni limpia servicios o volúmenes existentes. Conserva/restaura la variable de conexión de prueba sin imprimirla.

Desde la raíz del backend, con dependencias, cliente Prisma generado y Docker disponibles:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-session-security.ps1 -DatabaseRepository 'ruta-del-repositorio-smarthome-database'
```

El parámetro puede omitirse cuando BD está en la carpeta `smarthome-database` dentro del backend. El PostgreSQL de prueba usa `Repeatable Read` por defecto; el repositorio debe establecer `ReadCommitted` en sus operaciones coordinadas.

## Resultado del 14/10/2026

**17 casos aprobados sobre PostgreSQL 16 desechable: 8 de persistencia/concurrencia y 9 de flujo HTTP/Socket.IO.** Se ejecutan el repositorio Prisma, los casos de uso de sesión, guard JWT, firmador y transporte reales. Usuario, verificación de contraseña y autorización del hogar del flujo integrado son fixtures; el LOGIN de la fixture no representa uno de mínimo privilegio.

Los casos incluyen competencia entre refresh, logout/rotación en ambos órdenes con observación de bloqueos en `pg_locks`, rollback de una inserción fallida, vínculo usuario/versión, separación de familias, logout con cookie reemplazada, reutilización y rechazo de tokens sin familia. No se considera aprobada esta evidencia si Jest omite los casos por falta de `SESSION_TEST_DATABASE_URL`.

El backend también conserva 82 pruebas unitarias y 68 de regresión aislada aprobadas. Las seis pruebas históricas del diagnóstico de roles no se repitieron: ese SQL no cambia.

## Compatibilidad y pendientes

Los access tokens antiguos sin `sid` se rechazan; un refresh válido puede emitir el nuevo contrato, o el cliente debe repetir login. Las renovaciones simultáneas de la misma familia se consideran reutilización y pueden invalidar la respuesta de una renovación ganadora: los clientes deben coordinarlas.

Continúan pendientes los LOGIN/RLS reales, usuarios de hogares distintos, historial incremental, clientes web/móvil, proxy/WSS, carga y coordinación inmediata entre réplicas. Una solicitud ya autorizada o un paquete ya enviado no puede retirarse. HU09 y BD-17 permanecen abiertos.

Contrato completo y alcance de pruebas: [reporte del cuarto incremento de backend](https://github.com/nataliachala1/smarthome-backend/blob/6b033fe/docs/HU09_SESSION_FAMILIES.md).
