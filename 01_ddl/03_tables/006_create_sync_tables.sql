-- ============================================================
-- TABLAS - sync
-- Modelo vigente: únicamente metadata de backups.
-- ============================================================

CREATE TABLE IF NOT EXISTS sync.backup (
  id_backup   UUID        NOT NULL DEFAULT gen_random_uuid(),
  id_user     UUID        NULL,
  type        VARCHAR(20) NOT NULL,
  scope       VARCHAR(20) NOT NULL DEFAULT 'completo',
  location    TEXT        NOT NULL,
  size_bytes  BIGINT      NULL,
  status      VARCHAR(20) NOT NULL DEFAULT 'en_proceso',
  description TEXT        NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_backup PRIMARY KEY (id_backup),
  CONSTRAINT ck_backup_type CHECK (type IN ('automatico', 'manual')),
  CONSTRAINT ck_backup_scope CHECK (scope IN ('completo', 'parcial')),
  CONSTRAINT ck_backup_status CHECK (status IN ('en_proceso', 'completado', 'fallido')),
  CONSTRAINT ck_backup_size CHECK (size_bytes IS NULL OR size_bytes > 0)
);
