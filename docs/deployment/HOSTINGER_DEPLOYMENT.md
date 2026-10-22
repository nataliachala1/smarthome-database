# Hostinger y Dokploy

El VPS tiene Ubuntu 24.04 con Docker y Dokploy. La integración de Hostinger no permite inspeccionar contenedores en este sistema operativo y el acceso SSH desde este entorno aún no autentica. Por ahora, no se debe crear un proyecto ni activar un despliegue desde Dokploy.

## Auditoría requerida antes de conectar Dokploy

1. Accede al VPS por SSH desde una sesión de VS Code Remote-SSH usando la clave local ya registrada en Hostinger.
2. Inspecciona los servicios, contenedores, redes, volúmenes y la instancia de PostgreSQL 18 que ya existe. No modifiques los directorios internos de Dokploy.
3. Identifica el host de PostgreSQL, base, usuarios, red compartida, esquema, tabla `databasechangelog` y último changeset aplicado.
4. Crea un `pg_dump` completo y guárdalo fuera del VPS. Restaura una copia en una instancia aislada y verifica tablas y conteos.
5. Compara los changesets pendientes con la base restaurada. No ejecutes cambios destructivos ni migres producción mientras existan dudas sobre el historial.

## Configuración después de la auditoría

El Compose de este repositorio no crea un servidor PostgreSQL. Completa las variables de [ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md) con los nombres reales de la base existente y las redes identificadas. Revisa **Preview Compose** para confirmar que Liquibase y el backend llegan a la base existente y solo el frontend recibe el dominio público de Dokploy.

Configura acceso a los paquetes GHCR, dominio frontend, TLS y secretos en Dokploy. Mantén deshabilitado el job de despliegue de GitHub Actions hasta terminar estas comprobaciones y crear un único workflow coordinador que serialice las publicaciones de los tres repositorios.

La IP del VPS y el DNS del dominio ya se habían comprobado en la cuenta. No se han realizado cambios de despliegue en el VPS desde este repositorio.
