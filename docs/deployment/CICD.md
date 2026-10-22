# CI/CD en la rama `dev`

Cada repositorio tiene `.github/workflows/ci-deploy.yml`, activado por push a `dev`.

| Repositorio | Comprobaciones antes de publicar |
| --- | --- |
| Backend | `npm ci`, ESLint sin auto-fix, TypeScript, pruebas Jest y `nest build` |
| Frontend | `npm ci`, ESLint, `tsc --noEmit` y `vite build` |
| Base de datos | Liquibase `validate`, aplicación de todos los changesets en PostgreSQL 18 efímero, `status` y validación de Compose |

Tras las comprobaciones, backend y frontend publican en GHCR las etiquetas `dev` y el SHA del commit. Si el job anterior termina correctamente, el workflow llama al webhook de Dokploy y espera hasta seis minutos a que responda la URL de salud configurada.

El job de despliegue permanece deshabilitado mientras se verifica el VPS y se prueba la restauración de la base existente. No lo habilites hasta completar esa auditoría y configurar Dokploy y los secretos requeridos en los tres repositorios.

## Secretos requeridos en cada repositorio GitHub

- `DOKPLOY_DEPLOY_WEBHOOK`: URL privada de deploy del servicio Compose en Dokploy.
- `DEPLOYMENT_HEALTH_URL`: URL HTTPS del frontend con ruta `/health/live`, que Nginx reenvía al backend. El healthcheck interno usa `/health/ready`, incluyendo PostgreSQL.

El token `GITHUB_TOKEN` es provisto por Actions para publicar paquetes. No se guarda un token personal en el repositorio.

## Fallos y recuperación

Si lint, tipos, pruebas, compilación o validación de migraciones falla, los jobs posteriores no se ejecutan y no se llama a Dokploy. Si no pasa el chequeo de salud, Actions falla y conserva los logs del intento. Revisa el despliegue y vuelve a seleccionar en Dokploy la etiqueta SHA de la versión anterior para restaurar la aplicación.

El workflow no revierte automáticamente cambios de esquema: los cambios Liquibase deben ser compatibles hacia atrás y tener rollback revisado. Antes de una migración de datos, debe existir un backup verificado. El workflow no puede confirmar el estado real del VPS ni emitir un rollback de datos.
