-- ============================================================
-- TABLAS - homes
-- ============================================================

CREATE TABLE IF NOT EXISTS homes.home (
  id_home    UUID         NOT NULL DEFAULT gen_random_uuid(),
  created_by UUID         NOT NULL,
  name       VARCHAR(100) NOT NULL,
  stratum    SMALLINT     NOT NULL,
  status     VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
  created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ  NULL,
  CONSTRAINT pk_home PRIMARY KEY (id_home),
  CONSTRAINT uq_home_name UNIQUE (created_by, name),
  CONSTRAINT ck_home_stratum CHECK (stratum BETWEEN 1 AND 6),
  CONSTRAINT ck_home_status CHECK (status IN ('ACTIVE', 'DEACTIVATED')),
  CONSTRAINT ck_home_lifecycle CHECK (
    (status = 'ACTIVE' AND deleted_at IS NULL)
    OR (status = 'DEACTIVATED' AND deleted_at IS NOT NULL)
  )
);

CREATE TABLE IF NOT EXISTS homes.zone (
  id_zone    UUID         NOT NULL DEFAULT gen_random_uuid(),
  id_home    UUID         NOT NULL,
  name       VARCHAR(100) NOT NULL,
  type       VARCHAR(50)  NULL,
  created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ  NULL,
  CONSTRAINT pk_zone PRIMARY KEY (id_zone),
  CONSTRAINT uq_zone_name UNIQUE (id_home, name),
  CONSTRAINT uq_zone_home_identity UNIQUE (id_zone, id_home)
);

CREATE TABLE IF NOT EXISTS homes.electricity_tariff (
  id_electricity_tariff UUID          NOT NULL DEFAULT gen_random_uuid(),
  id_home               UUID          NOT NULL,
  price_per_kwh         NUMERIC(10,4) NOT NULL,
  currency              VARCHAR(10)   NOT NULL DEFAULT 'COP',
  valid_from            DATE          NOT NULL,
  valid_to              DATE          NULL,
  created_by            UUID          NOT NULL,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_electricity_tariff PRIMARY KEY (id_electricity_tariff),
  CONSTRAINT ck_electricity_tariff_price CHECK (price_per_kwh > 0),
  CONSTRAINT ck_electricity_tariff_validity CHECK (valid_to IS NULL OR valid_to > valid_from)
);

ALTER TABLE homes.electricity_tariff
  ADD CONSTRAINT ex_electricity_tariff_no_overlap
  EXCLUDE USING gist (
    id_home WITH =,
    daterange(valid_from, COALESCE(valid_to, 'infinity'::DATE), '[)') WITH &&
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
