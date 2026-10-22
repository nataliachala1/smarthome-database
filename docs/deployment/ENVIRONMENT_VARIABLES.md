# Variables de producción

Configúralas en Dokploy como variables del servicio Compose. `.env.production.example` contiene solo valores ficticios para comprobar la sintaxis; no copies esos valores a producción.

| Variable | Uso |
| --- | --- |
| `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` | Base y rol propietario/migrador. Usa una contraseña larga y única. |
| `APP_DB_PASSWORD`, `IOT_DB_PASSWORD` | Contraseñas únicas de los LOGIN del backend y la ingesta. El job `db-roles` las crea/actualiza con permisos mínimos tras Liquibase. |
| `DATABASE_URL` | URL PostgreSQL del LOGIN miembro de `smarthome_app`. |
| `DATABASE_IOT_URL` | URL PostgreSQL del LOGIN miembro de `smarthome_ingest`. |
| `JWT_SECRET`, `JWT_REFRESH_SECRET` | Secretos distintos y aleatorios; `JWT_SECRET` debe tener al menos 32 bytes. |
| `CORS_ALLOWED_ORIGINS` | Origen HTTPS exacto del frontend, sin rutas ni barra adicional. |
| `FRONTEND_URL` | URL primaria del frontend para enlaces de activación y recuperación; un solo origen HTTPS. |
| `MQTT_BROKER_URL`, `MQTT_USERNAME`, `MQTT_PASSWORD` | EMQX Cloud con esquema `mqtts://` y usuario de backend con privilegios mínimos. |
| `MQTT_TOPIC_NAMESPACE` | Namespace de producción acordado con EMQX, por ejemplo `smarthome/production/v1`. |
| `MQTT_TLS_CA_FILE` | Opcional. Vacío usa las CA confiables del sistema. No desactives validación TLS. |
| `COOKIE_SAME_SITE` | `lax` si web y API usan el mismo origen/proxy. |
| `TRUSTED_PROXY_CIDRS` | CIDRs reales del proxy Dokploy, solo después de confirmarlos. Vacío ignora headers de IP reenviados. |
| `BACKUP_RETENTION_DAYS` | Retención de dumps locales; valor inicial 30 días. |
| `BACKEND_IMAGE_TAG`, `FRONTEND_IMAGE_TAG` | `dev` en operación normal. Para rollback, usa el SHA de imagen previamente publicado. |

Las contraseñas incluidas en una URL PostgreSQL deben codificar caracteres reservados de URL. No agregues `VITE_*` secretos: Vite los incrusta en los archivos públicos del navegador.

Los roles técnicos `smarthome_app` y `smarthome_ingest` son `NOLOGIN`; el job `db-roles` crea LOGIN separados y les otorga solo esas membresías. No uses `smarthome_owner` como credencial del backend. Usa contraseñas alfanuméricas aleatorias para simplificar URLs PostgreSQL, que deben coincidir con `APP_DB_PASSWORD`/`IOT_DB_PASSWORD`.
