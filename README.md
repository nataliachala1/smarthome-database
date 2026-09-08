# Smart Home Database

Alcance del 8 de septiembre: [migración a dispositivos por hogar, validaciones y pendientes](./VALIDACION_FINAL.md). El historial anterior se conserva y la nueva migración aún no se ha aplicado a la base local original.

Baseline PostgreSQL + Liquibase para Smart Home.

## Componentes activos

- `01_ddl`: extensiones, esquemas, tablas, integridad, funciones técnicas, triggers de `updated_at` e índices.
- `02_dml`: catálogos determinísticos mínimos (`SYSTEM_ADMIN`, `USER`) y tipos iniciales de dispositivo.
- `03_dcl`: roles técnicos PostgreSQL, privilegios mínimos y Row Level Security.
- `04_tcl`: sin scripts de negocio. Las transacciones funcionales pertenecen a NestJS + Prisma.
- `05_rollbacks`: rollback de todos los changeSets activos.

Las views, materialized views y procedures heredadas fueron retiradas del baseline porque pertenecían al modelo anterior o duplicaban lógica de negocio.

## Inicio local

1. Copiar `.env.example` a `.env` y cambiar `POSTGRES_PASSWORD`.
2. Ejecutar `docker compose up -d postgres`.
3. Validar: `docker compose run --rm liquibase --defaults-file=liquibase.properties validate`.
4. Revisar SQL: `docker compose run --rm liquibase --defaults-file=liquibase.properties update-sql`.
5. Aplicar: `docker compose run --rm liquibase --defaults-file=liquibase.properties update`.

> `smarthome_owner` es el usuario bootstrap/migrador del entorno local. Los roles `smarthome_app`, `smarthome_ingest`, `smarthome_worker`, `smarthome_readonly` y `smarthome_admin` son roles PostgreSQL `NOLOGIN`; las cuentas LOGIN y sus membresías se provisionan fuera de estas migraciones.

## Contexto RLS desde Prisma

La conexión funcional debe usar un LOGIN miembro de `smarthome_app`. Cada transacción de aplicación debe establecer el usuario funcional solo para esa transacción:

```sql
SELECT set_config('app.current_user_id', '<uuid>', true);
```

No utilizar un `SET` persistente sobre conexiones del pool.
