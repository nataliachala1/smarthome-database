# HU 09-dev · baseline y permisos de runtime

Actualización transversal en `16-dev`: [HU16 — consumo con RLS real](HU16_CONSUMPTION_ACCESS.md) y [puente de sesiones](HU09_SESSION_SCHEMA_BRIDGE.md). El ensayo del historial original reveló los objetos de sesión ausentes; se agregaron changesets y se aprobaron 28 casos con un LOGIN sin privilegios elevados sobre una BD nueva. El estado de una instalación existente sigue sin verificarse.

## Línea base y coordinación (BD-01)

- Repositorio BD: `nataliachala1/smarthome-database`, rama de trabajo `09-dev`, desde `03-dev` / `e18b2d0`.
- Backend compatible de partida: `nataliachala1/smarthome-backend`, `09-dev` / `8235727`.
- Incremento de configuración validado en backend: `7447822`. No requiere DDL ni cambia el contrato del esquema; la auditoría comprueba los permisos de las conexiones que use esa configuración.
- Se conserva `revision-dispositivos.txt` local sin incluirlo en los commits. No se modifican changesets existentes, roles instalados ni esquemas.
- El snapshot local difiere de `origin/dev`. **SIN VERIFICAR:** historial instalado y compatibilidad incremental desde una base existente. No ejecutar reinicio de volúmenes ni asumir que el snapshot es una migración incremental.

En esta HU backend y BD avanzan en paralelo: backend valida la configuración declarada y BD prepara la comprobación de privilegios reales. No hace falta un changeset nuevo para consultar los catálogos.

## Compatibilidad con límites HTTP (segundo incremento de BD-02)

El backend incorpora límites por IP y método del controlador en el commit [49d5e55](https://github.com/nataliachala1/smarthome-backend/commit/49d5e55), rama `09-dev`. Es compatible con el contenido funcional de BD `f097a0a`; no requiere nuevos changesets, tablas, índices ni grants. En este segundo incremento el cambio del repositorio BD es documental.

Las solicitudes que exceden su cuota reciben `429` antes de ejecutar los casos de uso. Esto incluye registro, login, recuperación de contraseña y reactivación. Los contadores residen en memoria acotada del proceso de API y no generan escrituras PostgreSQL. El límite de login por IP complementa el bloqueo de cuenta ya existente; no cambia los campos o reglas persistidas de intentos fallidos.

`/health/ready` y `/health` conservan su consulta de BD y quedan sujetos a la cuota general. `/health/live` está exento y no consulta BD. La protección por roles/RLS sigue siendo necesaria para cada operación permitida por el límite HTTP.

Evidencia del backend al 14/10/2026: **82 pruebas unitarias y 17 pruebas HTTP aisladas aprobadas**, además de compilación, TypeScript y ESLint de archivos cambiados. Las pruebas HTTP sustituyen casos de uso, Prisma y el guard JWT; verifican que no se invoquen operaciones por encima de la cuota, pero no demuestran aislamiento RLS, autenticación real ni carga sobre PostgreSQL. Las seis pruebas SQL del primer incremento no se repitieron porque no hubo cambios en SQL ni en su script de prueba.

Antes de integrar en staging se debe comprobar la IP efectiva detrás del proxy y revisar la solución de contadores si existen varias réplicas. Los privilegios reales, el historial aplicado y las pruebas multiusuario BD-03/BD-04 siguen pendientes. Contrato `429`, cuotas y límites operativos: [reporte del incremento de backend](https://github.com/nataliachala1/smarthome-backend/blob/49d5e55/docs/HU09_RATE_LIMITING.md).

## Compatibilidad con sesiones Socket.IO (tercer incremento, BD-17)

Backend compatible: [da0a5ca](https://github.com/nataliachala1/smarthome-backend/commit/da0a5ca), rama `09-dev`. Reutiliza el esquema funcional de BD `f097a0a`; no añade changesets ni modifica SQL, roles o índices.

La autenticación realtime comprueba `user.status`, el rol global y `user.session_version`. `logout-all` incrementa la versión existente y avisa a los sockets del mismo proceso antes de revocar los refresh tokens. Las comprobaciones por evento y periódicas detectan cambios visibles en las lecturas de cuenta; no sustituyen coordinación entre réplicas.

Antes de entregar detalles del hogar se consulta `home_member` con contexto RLS del destinatario. Se exige `id_user` e `id_home` coincidentes, `status = ACTIVE`, rol `OWNER` o `MEMBER`, `accepted_at` no nulo, `ended_at` nulo y hogar `ACTIVE` con `deleted_at` nulo. No se usa `home.created_by` como sustituto de membresía. GUEST no recibe estos detalles; el resumen básico sigue pendiente de definición. El contador personal de notificaciones no concede acceso a datos del hogar.

Resultado del backend al 14/10/2026: **82 pruebas unitarias y 66 pruebas de integración aisladas aprobadas**, incluyendo 49 casos nuevos de Socket.IO/concurrencia/resolución de módulo y 17 de regresión HTTP. Los JWT y clientes Socket.IO son reales; las lecturas de usuario y membresía y la persistencia de refresh se sustituyen por fixtures. Esto no valida RLS ni permisos instalados. Las seis pruebas SQL del primer incremento no se repitieron porque el SQL no cambió.

Pendiente BD-03/BD-04: ejecutar la matriz con conexiones PostgreSQL reales sin privilegios elevados, probar usuarios de hogares diferentes y cambios concurrentes de membresía, y medir el coste de consultas por evento. Lectura de permisos y envío de red no forman una transacción atómica; una revocación posterior a la lectura puede coincidir con una entrega en curso. No declarar BD-17 cerrado con la evidencia aislada.

Contrato, renovación por reconexión y límites de logout individual/WSS/múltiples instancias: [reporte de seguridad realtime](https://github.com/nataliachala1/smarthome-backend/blob/da0a5ca/docs/HU09_REALTIME_SECURITY.md).

## Familias de sesión (cuarto incremento, BD-17)

Backend [6b033fe](https://github.com/nataliachala1/smarthome-backend/commit/6b033fe) agrega `sid`, logout individual y rotación transaccional, reutilizando el esquema existente. Se incorpora una fixture de prueba, sin changesets. [Contrato y evidencia PostgreSQL](HU09_SESSION_FAMILIES.md): 17 casos con repositorio Prisma real aprobados; permisos/RLS instalados y operación distribuida pendientes. Esta evidencia complementa las pruebas aisladas de los incrementos anteriores.

## Auditoría de solo lectura (BD-02)

`scripts/audit-runtime-roles.sql` utiliza un LOGIN real de aplicación o ingesta, lee únicamente catálogos y termina la transacción con `ROLLBACK`. Requiere PostgreSQL 16 y psql. No consulta contraseñas ni datos de negocio.

Preparar la conexión fuera del repositorio mediante configuración de cliente segura. No pegar URI, contraseñas ni tokens en tickets, comandos registrados o salidas compartidas. No utilizar una conexión administrativa para obtener un PASS aparente.

Ejecutar únicamente en el entorno autorizado, una vez por conexión:

```powershell
# Conexión de aplicación ya configurada externamente para psql:
psql -X --set=ON_ERROR_STOP=1 --set=expected_role=smarthome_runtime_app --file=scripts/audit-runtime-roles.sql

# Conexión de ingesta configurada por separado:
psql -X --set=ON_ERROR_STOP=1 --set=expected_role=smarthome_ingest --file=scripts/audit-runtime-roles.sql
```

El resultado debe mostrar PASS en todas las filas de ambas conexiones. Cualquier FAIL bloquea la aceptación de permisos de runtime. `ON_ERROR_STOP` detiene errores SQL; las filas FAIL son diagnósticos y no cambian por sí mismas el código de salida de psql. Un consumidor automatizado debe comprobarlas explícitamente.

Comprueba pertenencia efectiva al rol esperado, separación aplicación/ingesta, ausencia de privilegios elevados propios o asumibles, RLS habilitado en tablas protegidas, ausencia de pertenencia a sus propietarios y ausencia de DELETE físico sobre dispositivos. Revisa tanto `session_user` como `current_user`, para no ocultar una conexión privilegiada detrás de `SET ROLE`.

Limitaciones: no demuestra que las políticas RLS sean semánticamente correctas, que el contexto funcional cambie sin filtraciones entre conexiones del pool, ni que la configuración del backend use estas conexiones. Son necesarias las pruebas multiusuario de BD-03/04. La propiedad de tablas y membresías se examina de forma conservadora; el diagnóstico no cambia permisos automáticamente.

## Pruebas de este incremento

`scripts/test-runtime-roles.ps1` crea un PostgreSQL 16 temporal, sin red ni puertos expuestos, con datos en memoria y sin credenciales reales. Monta únicamente la consulta de auditoría en modo lectura. No usa servicios ni volúmenes existentes; elimina solo el contenedor con identificador único que acaba de crear. Requiere Docker disponible y permiso para ejecutar ese entorno de prueba.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-roles.ps1
```

Resultado del 14/10/2026: **seis escenarios aprobados**. Detecta correctamente una conexión normal de aplicación/ingesta, un rol elevado asumible, el rol esperado incorrecto, un administrador oculto tras `SET ROLE` y RLS deshabilitado. Se corrigió una carrera del arranque inicial: la espera ahora comprueba el servidor definitivo por TCP loopback, no el servidor temporal de inicialización. No se ejecutó Liquibase ni se probaron políticas reales de negocio con estos fixtures.

Estado de ejecución contra los LOGIN de una instalación real: **SIN VERIFICAR**. No se consultó una BD en uso ni se cambió broker o Shelly. Antes de corregir roles instalados o ejecutar una migración operativa, presentar el cambio concreto, su riesgo y solicitar la autorización aplicable.

Referencias: [funciones de información de PostgreSQL 16](https://www.postgresql.org/docs/16/functions-info.html), [Row Security](https://www.postgresql.org/docs/16/ddl-rowsecurity.html).
