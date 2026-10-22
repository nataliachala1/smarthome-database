# Variables de produccion

Configuralas en Dokploy despues de identificar los valores reales en el VPS. El archivo `.env.production.example` contiene marcadores ficticios; no los copies a produccion ni los reemplaces por nombres supuestos.

| Variable | Uso |
| --- | --- |
| `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB` | Host, puerto y base de la instancia PostgreSQL existente. |
| `DATABASE_NETWORK` | Red Docker existente que permite a Compose acceder a PostgreSQL. |
| `DOKPLOY_NETWORK` | Red externa que usa Traefik/Dokploy para acceder al frontend. |
| `LIQUIBASE_DB_USER`, `LIQUIBASE_DB_PASSWORD` | Cuenta de migracion identificada y revisada. |
| `DATABASE_URL` | URL PostgreSQL del login de aplicacion. |
| `DATABASE_IOT_URL` | URL PostgreSQL del login de ingesta. |
| `JWT_SECRET`, `JWT_REFRESH_SECRET` | Secretos distintos y aleatorios; JWT_SECRET debe tener al menos 32 bytes. |
| `CORS_ALLOWED_ORIGINS` | Origen HTTPS exacto del frontend, sin rutas ni barra adicional. |
| `FRONTEND_URL` | URL primaria HTTPS para enlaces de activacion y recuperacion. |
| `MQTT_ENABLED` | `false` mantiene la API arriba sin broker; cambia a `true` solo tras configurar MQTT TLS. |
| `MQTT_BROKER_URL`, `MQTT_USERNAME`, `MQTT_PASSWORD` | Broker con esquema `mqtts://` y usuario de backend; requeridos con MQTT habilitado. |
| `MQTT_TOPIC_NAMESPACE` | Namespace de produccion acordado con el broker; requerido con MQTT habilitado. |
| `MQTT_TLS_CA_FILE` | Opcional. Vacio usa las CA confiables del sistema. No desactives validacion TLS. |
| `EMAIL_ENABLED` | `false` permite iniciar sin SMTP; las operaciones que envian correo quedan temporalmente no disponibles. |
| `SMTP_USER`, `SMTP_APP_PASSWORD` | Cuenta Gmail y contrasena de aplicacion; requeridas con correo habilitado. No uses la contrasena normal de Gmail. |
| `SMTP_FROM` | Opcional. Remitente permitido por Gmail; por defecto se usa SMTP_USER. |
| `COOKIE_SAME_SITE` | `lax` si frontend y API usan el mismo origen/proxy. |
| `TRUSTED_PROXY_CIDRS` | CIDRs reales del proxy Dokploy, solo despues de confirmarlos. Vacio ignora headers de IP reenviados. |
| `BACKEND_IMAGE_TAG`, `FRONTEND_IMAGE_TAG` | `dev` en operacion normal. Para rollback, usa el SHA de imagen publicado. |

Codifica los caracteres reservados de URL en las contrasenas PostgreSQL. No agregues secretos `VITE_*`: Vite los incluye en los archivos publicos del navegador.

Antes del primer despliegue, verifica que los dos logins de aplicacion existan y tengan los permisos correctos en el esquema real. Revisa las migraciones pendientes tras verificar el backup restaurado.
