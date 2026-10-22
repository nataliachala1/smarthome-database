# Variables de producción

Configúralas en Dokploy después de identificar los valores reales en el VPS. `.env.production.example` contiene marcadores ficticios para comprobar sintaxis; no los copies a producción ni los reemplaces por nombres supuestos.

| Variable | Uso |
| --- | --- |
| `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB` | Host, puerto y base de la instancia PostgreSQL existente, identificados durante la auditoría. |
| `DATABASE_NETWORK` | Red Docker existente que permite a Compose acceder a PostgreSQL. |
| `DOKPLOY_NETWORK` | Red externa que usa Traefik/Dokploy para acceder al frontend. |
| `LIQUIBASE_DB_USER`, `LIQUIBASE_DB_PASSWORD` | Cuenta de migración existente, con permisos revisados para los changesets pendientes. No se crean roles automáticamente. |
| `DATABASE_URL` | URL PostgreSQL del login de aplicación ya verificado. |
| `DATABASE_IOT_URL` | URL PostgreSQL del login de ingesta ya verificado. |
| `JWT_SECRET`, `JWT_REFRESH_SECRET` | Secretos distintos y aleatorios; `JWT_SECRET` debe tener al menos 32 bytes. |
| `CORS_ALLOWED_ORIGINS` | Origen HTTPS exacto del frontend, sin rutas ni barra adicional. |
| `FRONTEND_URL` | URL primaria HTTPS para enlaces de activación y recuperación. |
| `MQTT_BROKER_URL`, `MQTT_USERNAME`, `MQTT_PASSWORD` | EMQX Cloud con esquema `mqtts://` y usuario de backend con privilegios mínimos. |
| `MQTT_TOPIC_NAMESPACE` | Namespace de producción acordado con EMQX, por ejemplo `smarthome/production/v1`. |
| `MQTT_TLS_CA_FILE` | Opcional. Vacío usa las CA confiables del sistema. No desactives validación TLS. |
| `COOKIE_SAME_SITE` | `lax` si frontend y API usan el mismo origen/proxy. |
| `TRUSTED_PROXY_CIDRS` | CIDRs reales del proxy Dokploy, solo después de confirmarlos. Vacío ignora headers de IP reenviados. |
| `BACKEND_IMAGE_TAG`, `FRONTEND_IMAGE_TAG` | `dev` en operación normal. Para rollback, usa el SHA de imagen previamente publicado. |

Codifica los caracteres reservados de URL en las contraseñas PostgreSQL. No agregues `VITE_*` secretos: Vite los incrusta en los archivos públicos del navegador.

Antes del primer despliegue, verifica que los dos logins de aplicación existan y tengan los permisos correctos en el esquema real. Una migración pendiente que requiera permisos nuevos debe revisarse y ejecutarse solo después de verificar el backup restaurado.
