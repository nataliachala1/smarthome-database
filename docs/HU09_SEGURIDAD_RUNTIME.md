# HU 09-dev · baseline y permisos de runtime

## Línea base y coordinación (BD-01)

- Repositorio BD: `nataliachala1/smarthome-database`, rama de trabajo `09-dev`, desde `03-dev` / `e18b2d0`.
- Backend compatible de partida: `nataliachala1/smarthome-backend`, `09-dev` / `8235727`.
- Incremento de configuración validado en backend: `7447822`. No requiere DDL ni cambia el contrato del esquema; la auditoría comprueba los permisos de las conexiones que use esa configuración.
- Se conserva `revision-dispositivos.txt` local sin incluirlo en los commits. No se modifican changesets existentes, roles instalados ni esquemas.
- El snapshot local difiere de `origin/dev`. **SIN VERIFICAR:** historial instalado y compatibilidad incremental desde una base existente. No ejecutar reinicio de volúmenes ni asumir que el snapshot es una migración incremental.

En esta HU backend y BD avanzan en paralelo: backend valida la configuración declarada y BD prepara la comprobación de privilegios reales. No hace falta un changeset nuevo para consultar los catálogos.

## Auditoría de solo lectura (BD-02)

`scripts/audit-runtime-roles.sql` utiliza un LOGIN real de aplicación o ingesta, lee únicamente catálogos y termina la transacción con `ROLLBACK`. Requiere PostgreSQL 16 y psql. No consulta contraseñas ni datos de negocio.

Preparar la conexión fuera del repositorio mediante configuración de cliente segura. No pegar URI, contraseñas ni tokens en tickets, comandos registrados o salidas compartidas. No utilizar una conexión administrativa para obtener un PASS aparente.

Ejecutar únicamente en el entorno autorizado, una vez por conexión:

```powershell
# Conexión de aplicación ya configurada externamente para psql:
psql -X --set=ON_ERROR_STOP=1 --set=expected_role=smarthome_app --file=scripts/audit-runtime-roles.sql

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
