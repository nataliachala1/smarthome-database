-- ============================================================
-- TABLAS - homes
-- ============================================================

CREATE TABLE IF NOT EXISTS homes.home (
  id_home    UUID         NOT NULL DEFAULT gen_random_uuid(),
  created_by UUID         NOT NULL,
  name       VARCHAR(100) NOT NULL,
  status     VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
  created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ  NULL,
  CONSTRAINT pk_home PRIMARY KEY (id_home),
  CONSTRAINT uq_home_name UNIQUE (created_by, name),
  CONSTRAINT ck_home_status CHECK (status IN ('ACTIVE', 'DEACTIVATED')),
  CONSTRAINT ck_home_lifecycle CHECK (
    (status = 'ACTIVE' AND deleted_at IS NULL)
    OR (status = 'DEACTIVATED' AND deleted_at IS NOT NULL)
  )
);

CREATE TABLE IF NOT EXISTS homes.home_member (
  id_home_member UUID        NOT NULL DEFAULT gen_random_uuid(),
  id_home        UUID        NOT NULL,
  id_user        UUID        NOT NULL,
  role           VARCHAR(10) NOT NULL,
  status         VARCHAR(10) NOT NULL DEFAULT 'PENDING',
  invited_by     UUID        NULL,
  invited_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  accepted_at    TIMESTAMPTZ NULL,
  ended_at       TIMESTAMPTZ NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_home_member PRIMARY KEY (id_home_member),
  CONSTRAINT ck_home_member_role CHECK (role IN ('OWNER', 'MEMBER', 'GUEST')),
  CONSTRAINT ck_home_member_status CHECK (status IN ('PENDING', 'ACTIVE', 'REVOKED', 'LEFT')),
  CONSTRAINT ck_home_member_dates CHECK (
    (status = 'PENDING' AND accepted_at IS NULL AND ended_at IS NULL)
    OR (status = 'ACTIVE' AND accepted_at IS NOT NULL AND ended_at IS NULL)
    OR (status IN ('REVOKED', 'LEFT') AND ended_at IS NOT NULL)
  )
);
