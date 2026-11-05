-- ============================================================
-- TABLAS - auth
-- ============================================================

CREATE TABLE IF NOT EXISTS auth.role (
  id_role     UUID        NOT NULL DEFAULT gen_random_uuid(),
  name        VARCHAR(20) NOT NULL,
  description TEXT        NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_role PRIMARY KEY (id_role),
  CONSTRAINT uq_role_name UNIQUE (name),
  CONSTRAINT ck_role_name CHECK (name IN ('SYSTEM_ADMIN', 'USER'))
);

CREATE TABLE IF NOT EXISTS auth."user" (
  id_user               UUID         NOT NULL DEFAULT gen_random_uuid(),
  id_role               UUID         NOT NULL DEFAULT 'a1b2c3d4-0001-0000-0000-000000000002'::UUID,
  name                  VARCHAR(100) NOT NULL,
  email                 VARCHAR(255) NOT NULL,
  password_hash         TEXT         NOT NULL,
  status                VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
  email_verified        BOOLEAN      NOT NULL DEFAULT FALSE,
  failed_login_attempts SMALLINT     NOT NULL DEFAULT 0,
  locked_until          TIMESTAMPTZ  NULL,
  last_login_at         TIMESTAMPTZ  NULL,
  deactivated_at        TIMESTAMPTZ  NULL,
  created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_user PRIMARY KEY (id_user),
  CONSTRAINT ck_user_status CHECK (status IN ('PENDING', 'ACTIVE', 'DEACTIVATED', 'LOCKED')),
  CONSTRAINT ck_user_failed_attempts CHECK (failed_login_attempts >= 0),
  CONSTRAINT ck_user_deactivated_state CHECK (
    (status = 'DEACTIVATED' AND deactivated_at IS NOT NULL)
    OR (status <> 'DEACTIVATED' AND deactivated_at IS NULL)
  ),
  CONSTRAINT ck_user_locked_state CHECK (
    status <> 'LOCKED' OR locked_until IS NOT NULL
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_email_lower
  ON auth."user" (LOWER(email));

CREATE TABLE IF NOT EXISTS auth.recovery_token (
  id_recovery_token UUID        NOT NULL DEFAULT gen_random_uuid(),
  id_user           UUID        NOT NULL,
  token_hash        TEXT        NOT NULL,
  type              VARCHAR(30) NOT NULL,
  expires_at        TIMESTAMPTZ NOT NULL,
  used_at           TIMESTAMPTZ NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_recovery_token PRIMARY KEY (id_recovery_token),
  CONSTRAINT uq_recovery_token_hash UNIQUE (token_hash),
  CONSTRAINT ck_recovery_token_type CHECK (
    type IN ('PASSWORD_RESET', 'ACCOUNT_ACTIVATION', 'ACCOUNT_REACTIVATION')
  ),
  CONSTRAINT ck_recovery_token_expiry CHECK (expires_at > created_at),
  CONSTRAINT ck_recovery_token_used_at CHECK (used_at IS NULL OR used_at >= created_at)
);

CREATE INDEX IF NOT EXISTS idx_recovery_token_user
  ON auth.recovery_token (id_user);
