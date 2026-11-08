# SmartHome Database

Base de datos relacional del proyecto **SmartHome**, desarrollada sobre **PostgreSQL** y administrada mediante **Liquibase**.

Este repositorio contiene el esquema de datos, las migraciones SQL versionadas, los catálogos iniciales, los roles PostgreSQL, los privilegios de acceso y las políticas de seguridad necesarias para el funcionamiento del sistema SmartHome.

La base de datos proporciona persistencia a los módulos de autenticación, hogares, dispositivos IoT, consumo energético, notificaciones y vinculación de dispositivos Shelly mediante MQTT.

## 1. Tecnologías

| Tecnología | Función |
|---|---|
| PostgreSQL | Motor de base de datos relacional |
| SQL | Definición, consulta, manipulación y control de acceso a datos |
| Liquibase 4.29 | Versionamiento y aplicación de migraciones |
| YAML | Definición de changelogs Liquibase |
| Docker | Entornos de ejecución aislados |
| Docker Compose | Orquestación local de PostgreSQL y Liquibase |
| Prisma | Integración del esquema con el backend NestJS |
| Git y GitHub | Versionamiento, revisión e integración de cambios |

El entorno local declarado en `docker-compose.yml` utiliza PostgreSQL 18 Alpine, la misma versión del CI.

## 2. Arquitectura

SmartHome utiliza una arquitectura cliente-servidor con persistencia relacional en PostgreSQL.

La base de datos es consumida principalmente por el backend NestJS mediante conexiones y usuarios con permisos diferenciados.

El sistema se organiza de acuerdo con los siguientes principios:

- **Integridad referencial:** relaciones y restricciones que protegen la consistencia de los datos.
- **Normalización:** organización de la información para reducir redundancias.
- **Seguridad por roles:** usuarios técnicos con privilegios específicos.
- **Mínimo privilegio:** cada conexión accede únicamente a las operaciones autorizadas.
- **Row-Level Security (RLS):** protección del acceso a determinadas filas de datos.
- **Transaccionalidad:** operaciones consistentes mediante transacciones PostgreSQL.
- **Migraciones versionadas:** evolución controlada del esquema mediante Liquibase.
- **Separación de responsabilidades:** la lógica de negocio pertenece al backend; las restricciones, funciones técnicas y persistencia pertenecen a la base de datos.

Prisma actúa como herramienta de acceso desde el backend. El historial oficial de migraciones SQL se administra en este repositorio mediante Liquibase.

## 3. Estructura del repositorio

La estructura principal es:

```text
smarthome-database/
├── .github/
│   └── workflows/
├── 01_ddl/
├── 02_dml/
├── 03_dcl/
├── 04_tcl/
├── 05_rollbacks/
├── changelog/
│   └── changelog-master.yaml
├── releases/
├── scripts/
├── .env.example
├── .gitignore
├── docker-compose.yml
├── docker-compose.production.yml
├── liquibase.properties
└── README.md
```

### 3.1. Definición de datos — DDL

La carpeta `01_ddl/` organiza:

- Extensiones PostgreSQL.
- Esquemas.
- Tipos.
- Tablas.
- Modificaciones estructurales.
- Vistas.
- Vistas materializadas.
- Funciones técnicas.
- Procedimientos.
- Triggers.
- Índices.

Los elementos aplicados dependen de los changesets activos del historial Liquibase.

### 3.2. Datos iniciales — DML

La carpeta `02_dml/` contiene los datos iniciales y catálogos requeridos para el funcionamiento del sistema.

Incluye catálogos determinísticos vinculados con los roles y tipos de dispositivos.

`02_dml/90_demo/` contiene **datos de demostración ficticios** (usuarios de prueba, un hogar y un dispositivo). Solo se aplican con `changelog/changelog-demo.yaml`; `changelog/changelog-master.yaml`, que es el que se usa en QA y producción, no los incluye.

### 3.3. Control de acceso — DCL

La carpeta `03_dcl/` contiene definiciones de seguridad relacionadas con:

- Roles técnicos PostgreSQL.
- Privilegios de acceso.
- Políticas Row-Level Security.
- Restricciones de acceso a recursos.
- Separación de responsabilidades de las conexiones.

### 3.4. Transacciones — TCL

La carpeta `04_tcl/` forma parte de la organización del repositorio.

Las transacciones funcionales del sistema son gestionadas principalmente por el backend, utilizando PostgreSQL y Prisma.

### 3.5. Rollbacks

La carpeta `05_rollbacks/` contiene scripts de reversión asociados con las migraciones que disponen de esa capacidad.

**No todos los cambios son necesariamente reversibles sin pérdida de datos.**

Cualquier rollback debe revisarse antes de su ejecución.

### 3.6. Migraciones incrementales

La carpeta `releases/` contiene las migraciones que amplían o modifican el esquema después del baseline inicial.

El archivo principal de coordinación es:

`changelog/changelog-master.yaml`

Este changelog referencia las migraciones y establece el orden en que Liquibase debe procesarlas.

## 4. Módulos de información

La base de datos proporciona persistencia para los siguientes dominios funcionales.

| Dominio | Responsabilidad |
|---|---|
| Autenticación | Usuarios, roles, sesiones y tokens |
| Hogares | Gestión de hogares y miembros |
| Dispositivos | Registro, vinculación y estado de dispositivos IoT |
| Consumo | Mediciones eléctricas y registros energéticos |
| Configuración | Preferencias y parámetros del sistema |
| Notificaciones | Alertas y comunicaciones internas |
| Sincronización | Información relacionada con procesos de sincronización |
| Auditoría | Evidencias y registros de operaciones según el esquema implementado |

Las entidades y relaciones exactas están definidas en los scripts SQL y representadas, cuando corresponde, en el esquema Prisma del backend.

## 5. Seguridad

La base de datos utiliza diferentes mecanismos para controlar el acceso.

### 5.1. Usuarios y roles PostgreSQL

Se separan las responsabilidades de:

- Administración y migración del esquema.
- Operaciones funcionales de la aplicación.
- Ingesta de telemetría IoT.
- Procesamiento de métricas.
- Operaciones especializadas de MQTT.
- Consultas de solo lectura.

Los roles técnicos definidos como `NOLOGIN` no se utilizan directamente para establecer conexiones.

Las cuentas `LOGIN` reciben las membresías que correspondan a su función.

### 5.2. Row-Level Security

Las políticas RLS complementan los controles implementados en el backend.

Permiten restringir el acceso a información según el contexto de autorización establecido para cada operación.

El backend debe utilizar una cuenta con permisos limitados y establecer correctamente el contexto de usuario dentro de las transacciones correspondientes.

Ejemplo del contexto utilizado:

```sql
SELECT set_config(
  'app.current_user_id',
  '<uuid>',
  true
);
```

El contexto no debe configurarse de forma persistente en conexiones reutilizadas del pool.

### 5.3. Seguridad de conexiones

En los entornos desplegados se deben aplicar:

- Conexiones TLS verificadas.
- Credenciales administradas fuera del repositorio.
- Usuarios con privilegios mínimos.
- Restricciones de acceso a redes y servicios.
- Separación de cuentas de aplicación, ingesta y administración.
- Respaldos protegidos.
- Auditoría de permisos antes de cada migración.

No deben almacenarse contraseñas reales en archivos versionados.

## 6. Migraciones Liquibase

El historial de migraciones se administra mediante:

```text
changelog/changelog-master.yaml
```

Entre las migraciones presentes en la rama de desarrollo se encuentran:

| Migración | Finalidad principal |
|---|---|
| SQL018 | Permisos de hogares |
| SQL019 | Sesiones de vinculación de dispositivos |
| SQL020 | Compatibilidad del método LAN |
| SQL020a–SQL031 | Evolución de la vinculación y autorización MQTT |
| SQL032 | Revocación y reconciliación MQTT |
| SQL033 | Ingesta y actualización de información en tiempo real |
| SQL034 | Tarifas eléctricas y objetivos de consumo |
| SQL035 | Idempotencia de ingesta MQTT |
| SQL036 | Control de orden temporal de eventos |
| SQL037 | Restricción de privilegios de cuarentena de leases MQTT |

**Importante:** la presencia de una migración en GitHub no demuestra que ya haya sido aplicada a PostgreSQL.

Antes de ejecutar cualquier actualización sobre una base existente debe verificarse el historial real de `DATABASECHANGELOG`, la compatibilidad del backend y el estado de los permisos.

### Reglas de migración

1. No modificar changesets históricos que ya hayan sido aplicados.
2. Implementar cambios adicionales mediante nuevos changesets.
3. Revisar las dependencias entre migraciones.
4. Ejecutar primero las pruebas sobre una base PostgreSQL desechable.
5. Verificar los permisos, restricciones, funciones e índices afectados.
6. Revisar las operaciones de reversión.
7. Obtener un respaldo verificable antes de modificar una base compartida.
8. Coordinar los cambios que requieren actualizaciones simultáneas del backend.

## 7. Configuración local

### Requisitos

- Docker y Docker Compose.
- Git.
- Un entorno local de pruebas independiente.
- Acceso a las dependencias necesarias para PostgreSQL y Liquibase.

### Archivo de variables

El repositorio proporciona:

`.env.example`

Para preparar un entorno local:

```powershell
Copy-Item .env.example .env
```

Configurar los valores locales de:

```dotenv
POSTGRES_USER=smarthome_owner
POSTGRES_PASSWORD=CHANGE_ME_LOCAL_ONLY
POSTGRES_DB=smarthome
POSTGRES_PORT=5432
```

Sustituir `CHANGE_ME_LOCAL_ONLY` por una contraseña local adecuada.

El archivo `.env` no debe agregarse a Git.

### PostgreSQL local

El servicio PostgreSQL está definido en `docker-compose.yml`.

Para iniciar únicamente la base local de pruebas:

```powershell
docker compose up -d --wait postgres
```

Este comando debe utilizarse exclusivamente en un entorno de pruebas identificado y aislado.

No debe ejecutarse contra los contenedores ni volúmenes del VPS sin una revisión específica.

### Base local con usuarios de prueba

Para una instalación de evaluación o desarrollo, aplicar el esquema completo más los datos de demostración:

```powershell
docker compose up -d --wait postgres
docker compose run --rm liquibase --defaults-file=liquibase.properties --changelog-file=changelog/changelog-demo.yaml update
```

Usuarios creados (contraseña común: `SmartHome#2026`). Son ficticios y usan el dominio reservado `example.com`:

| Correo | Rol global | Rol en «Casa Demo» |
|---|---|---|
| `admin@example.com` | SYSTEM_ADMIN | — |
| `owner@example.com` | USER | OWNER |
| `member@example.com` | USER | MEMBER |
| `guest@example.com` | USER | GUEST |

Para retirarlos: `... --changelog-file=changelog/changelog-demo.yaml rollback-count --count=1`.

**Nunca** usar `changelog-demo.yaml` en QA ni en producción.

### Checksums y comentarios traducidos

El 2026-11-07 los comentarios SQL se tradujeron al inglés. Los changesets afectados declaran su checksum anterior en `validCheckSum`, de modo que las bases ya migradas siguen validando sin ejecutar `clear-checksums` ni volver a aplicar cambios.

## 8. Validación de migraciones

Para comprobar el changelog en una base de pruebas:

```powershell
docker compose run --rm liquibase --defaults-file=liquibase.properties validate
```

Para revisar el SQL previsto antes de aplicar cambios:

```powershell
docker compose run --rm liquibase --defaults-file=liquibase.properties update-sql
```

La aplicación de migraciones requiere una autorización independiente:

```powershell
docker compose run --rm liquibase --defaults-file=liquibase.properties update
```

**Advertencia:** el último comando modifica la base configurada. No ejecutarlo en QA o producción sin respaldo, revisión de cambios y aprobación.

Las pruebas locales no sustituyen la validación de una base existente.

## 9. Scripts auxiliares

La carpeta `scripts/` contiene utilidades relacionadas con la administración, validación o preparación de componentes PostgreSQL.

Entre los archivos identificados se encuentra:

`scripts/provision-runtime-roles.sql`

Este script contempla el aprovisionamiento de cuentas de aplicación e ingesta y sus membresías.

No debe ejecutarse automáticamente sobre una base compartida sin revisar sus efectos, especialmente cuando existen cuentas y contraseñas ya provisionadas.

Los demás scripts serán clasificados mediante una auditoría independiente para determinar cuáles son necesarios, cuáles deben trasladarse y cuáles pueden retirarse sin afectar las migraciones.

## 10. Estrategia de ramas y entornos

El repositorio adopta el siguiente flujo de trabajo:

| Rama | Propósito | Política |
|---|---|---|
| `dev` | Desarrollo e integración de cambios | Validaciones automáticas sin migrar el VPS |
| `qa` | Validación funcional e integración | Migraciones controladas sobre el entorno QA |
| `main` | Código aprobado para producción | Cambios sujetos a aprobación y controles de producción |

### Desarrollo

Las modificaciones se realizan en ramas hijas de `dev`.

Cada Pull Request debe revisar el impacto sobre el esquema, los permisos, las migraciones y la compatibilidad del backend.

### QA

La rama `qa` recibe los cambios aprobados desde desarrollo.

Antes de aplicar migraciones a la base QA se requiere:

- Confirmar el destino PostgreSQL.
- Validar el historial Liquibase.
- Revisar el SQL pendiente.
- Comprobar respaldos.
- Verificar roles y permisos.
- Coordinar la versión del backend.
- Ejecutar comprobaciones posteriores a la migración.

### Producción

La rama `main` representa el código destinado a producción.

Su despliegue debe permanecer separado de QA y requiere infraestructura, credenciales, mecanismos de respaldo y autorizaciones propias.

## 11. Docker y despliegue

- `docker-compose.yml`: servicios para desarrollo y pruebas locales.
- `docker-compose.production.yml`: configuración restringida para inspeccionar las migraciones en una instancia PostgreSQL existente.

El archivo `docker-compose.production.yml` no administra los despliegues del backend ni del frontend.

Liquibase permanece bajo el perfil `database-inspection` y utiliza `validate` como operación predeterminada.

Las migraciones reales, el aprovisionamiento de roles PostgreSQL y la rotación de credenciales requieren procedimientos independientes, revisados y autorizados.

La aplicación de migraciones sobre QA y producción permanecerá deshabilitada hasta completar la auditoría y verificar respaldos, certificados TLS, permisos y compatibilidad con el backend.

## 12. Integración con el backend

Repositorio:

https://github.com/nataliachala1/smarthome-backend

El backend utiliza NestJS, TypeScript y Prisma para consumir las operaciones de persistencia.

Las migraciones PostgreSQL y los permisos de las cuentas técnicas deben ser compatibles con la versión del backend que se pretende desplegar.

Especialmente en los flujos de Shelly y MQTT, una migración puede modificar permisos o contratos que el backend valida al iniciar.

Por ese motivo, **la integración de una nueva versión del backend no autoriza automáticamente la ejecución de migraciones sobre una base existente**.

## 13. Documentación técnica

La documentación funcional y arquitectónica se administra separadamente del código y de las migraciones.

Repositorio de documentación de referencia:

https://github.com/Kevin-Stiven-Lopez-Amaya404/smart-home-docs

La documentación retirada de este repositorio se entregó al responsable correspondiente para su revisión y organización.

La publicación y ubicación definitiva de esos documentos deberán verificarse en el repositorio documental.

Este README se concentra en explicar la finalidad del repositorio, su organización, configuración, seguridad y procedimiento general de trabajo.

## 14. Buenas prácticas de contribución

Antes de integrar cualquier modificación:

1. Crear una rama hija desde `dev`.
2. Comprobar que los cambios pertenecen al repositorio de base de datos.
3. No incorporar documentación externa, respaldos ni archivos temporales innecesarios.
4. Mantener intacto el historial Liquibase ya aplicado.
5. No incluir credenciales ni archivos `.env` reales.
6. Ejecutar las validaciones correspondientes en un entorno aislado.
7. Revisar el SQL generado antes de autorizar una migración.
8. Comprobar el impacto sobre las conexiones del backend.
9. Abrir un Pull Request hacia `dev`.
10. Obtener revisión antes de integrar los cambios.

## 15. Estado de preparación para QA

La rama `dev` contiene el historial de migraciones hasta SQL037.

La integración hacia `qa` y la actualización de PostgreSQL en el VPS requieren comprobaciones adicionales.

Pendientes principales:

- [ ] Completar limpieza y auditoría de archivos auxiliares.
- [ ] Validar íntegramente el changelog Liquibase.
- [ ] Preparar CI con PostgreSQL desechable.
- [ ] Confirmar el historial real de migraciones del VPS.
- [ ] Verificar SQL037 y los privilegios MQTT.
- [ ] Comprobar respaldos y restauración de prueba.
- [ ] Revisar la configuración de Docker y despliegue.
- [ ] Integrar los cambios aprobados en `qa`.
- [ ] Ejecutar la migración QA mediante un procedimiento controlado.
- [ ] Validar conectividad, permisos y funcionamiento del backend después de la migración.

**Estado:** repositorio en proceso de limpieza y preparación para integración QA. No se autoriza la ejecución automática de migraciones sobre el VPS.
