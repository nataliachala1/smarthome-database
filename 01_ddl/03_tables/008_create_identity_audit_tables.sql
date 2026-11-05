-- ============================================================
-- TABLA - identity_audit.audit_log
-- Auditoría semántica generada por NestJS. Append-only.
-- ============================================================

CREATE TABLE IF NOT EXISTS identity_audit.audit_log (
  id_audit_log UUID        NOT NULL DEFAULT gen_random_uuid(),
  id_user      UUID        NULL,
  id_home      UUID        NULL,
  actor_type   VARCHAR(20) NOT NULL DEFAULT 'USER',
  action       VARCHAR(80) NOT NULL,
  module       VARCHAR(50) NOT NULL,
  entity       VARCHAR(50) NULL,
  id_entity    UUID        NULL,
  result       VARCHAR(20) NULL,
  metadata     JSONB       NOT NULL DEFAULT '{}'::JSONB,
  ip_address   INET        NULL,
  user_agent   TEXT        NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_audit_log PRIMARY KEY (id_audit_log),
  CONSTRAINT ck_audit_log_actor_type CHECK (actor_type IN ('USER', 'SYSTEM', 'INFRASTRUCTURE')),
  CONSTRAINT ck_audit_log_result CHECK (result IS NULL OR result IN ('SUCCESS', 'FAILURE')),
  CONSTRAINT ck_audit_log_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

COMMENT ON TABLE identity_audit.audit_log IS
'Registro inmutable de eventos semánticos de auditoría generados explícitamente por NestJS.';
COMMENT ON COLUMN identity_audit.audit_log.metadata IS
'Contexto mínimo sanitizado. Nunca contiene contraseñas, hashes, JWT, tokens originales, credenciales MQTT ni secretos.';
