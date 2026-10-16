# HU14 — Observabilidad sin cambios de base de datos

Fecha: 2026-10-15. Rama `14-dev`, derivada de `09-dev`. El incremento HU14 instrumenta solicitudes HTTP y exporta métricas de proceso desde NestJS. No añade consultas de aplicación, telemetría persistida, changesets, tablas, roles, grants, políticas RLS ni índices.

La readiness existente conserva `SELECT 1` contra PostgreSQL. El endpoint `/metrics` y las métricas de latencia/estado son responsabilidad del backend y de la plataforma de observabilidad. La guía de integración, scrape autenticado, ejemplos de alertas y límites operativos están en el backend: `docs/HU14_OBSERVABILITY_METRICS.md`.

No se ejecutó DDL ni se requiere migrar la base para este incremento. No añadir índices sin evidencia de consultas lentas y mediciones de staging.
