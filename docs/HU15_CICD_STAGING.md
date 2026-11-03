# HU15 — CI de base de datos y preparación de staging

Fecha: 2026-10-15. Rama `15-dev`, derivada de `09-dev`. Este incremento no añade ni ejecuta changesets en una base compartida.

## CI

`.github/workflows/liquibase-ci.yml` valida el changelog y aplica todos los changesets a un servicio PostgreSQL 16 desechable en GitHub Actions. Luego verifica que Liquibase no detecte cambios pendientes. Corre en push, pull request y ejecución manual para ramas `09-dev` a `16-dev`, usa permiso de contenido de solo lectura y fija `actions/checkout` al SHA revisado.

La contraseña del job es sintética y existe solo para el contenedor efímero. No se cargan `.env`, credenciales ni snapshots productivos. CI comprueba reproducibilidad de la historia Liquibase; no certifica permisos, extensiones, datos ni configuración de una instalación real.

## Staging

No hay target o proveedor de staging definido. Esta rama prepara validación automatizada, pero no crea infraestructura, no publica imágenes ni conecta a una base externa. El backend mantiene por separado la guía de build y preflight en `docs/HU15_CICD_STAGING.md`.

Antes de un despliegue real se necesita una base aislada, TLS, secretos en el gestor del proveedor, usuarios de mínimo privilegio, política de backups/retención, método de aplicar migraciones, healthchecks y procedimiento de rollback. Las migraciones que eliminan o transforman datos requieren revisión y ventana aprobada. Nunca apuntar este workflow a producción.

**Cambios de base:** ninguno. No se generan archivos Liquibase ni se altera el baseline.
