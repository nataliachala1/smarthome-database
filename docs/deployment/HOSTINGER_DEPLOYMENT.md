# Preparar Hostinger y Dokploy

## Requisitos

- VPS Ubuntu 24.04 con Docker, Dokploy y espacio libre para imágenes y dumps.
- Acceso desde Dokploy a los repositorios GitHub y al paquete GHCR de cada aplicación.
- Un dominio frontend con DNS A/AAAA apuntando al VPS.
- Una instancia EMQX Cloud con endpoint TLS, usuario de servicio, ACL y namespace configurados.

## Dokploy

1. Crea un servicio **Docker Compose** y conecta `nataliachala1/smarthome-database`, rama `dev`, archivo `docker-compose.production.yml`.
2. Configura la lectura de los dos paquetes GHCR. Si los paquetes son privados, autoriza el registry en Dokploy.
3. Añade las variables de [ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md) en el entorno de Compose de Dokploy.
4. Configura el dominio del frontend en el puerto interno `8080` desde la pestaña Domains de Dokploy y habilita TLS/Let's Encrypt.
5. Usa el webhook de deploy de ese servicio como secreto `DOKPLOY_DEPLOY_WEBHOOK` en los tres repositorios.
6. Añade en cada repositorio `DEPLOYMENT_HEALTH_URL` con la URL HTTPS pública `https://<dominio>/health/live`.
7. Configura Actions para permitir publicar paquetes en GHCR. Los workflows usan `GITHUB_TOKEN` y necesitan `packages: write`.

Dokploy permite auto deploy para aplicaciones y servicios Compose; la rama configurada debe ser exactamente `dev`. Revisa **Preview Compose** antes de activar el servicio y confirma que únicamente el frontend está conectado a la red de routing pública.

## Orden inicial seguro

No inicies una primera aplicación contra una base existente sin revisar la instalación. Confirma versión de PostgreSQL, volúmenes, esquema, tabla `databasechangelog` y último changeset. Guarda un `pg_dump` en ubicación externa y prueba restaurarlo en una base aislada. El changelog principal está pensado para desplegar el baseline; una base existente sin historial Liquibase podría rechazarlo.

Primero configura y valida el endpoint de salud, dominio, TLS, acceso a GHCR y variables; luego realiza la primera ejecución en una ventana de mantenimiento. Mantén disponible la versión anterior de las imágenes GHCR etiquetada por SHA.

La configuración del firewall, DNS, certificados, secretos, registry y panel de Dokploy solo puede completarse con acceso a las cuentas del propietario. No se han realizado cambios en el VPS desde esta carpeta local.
