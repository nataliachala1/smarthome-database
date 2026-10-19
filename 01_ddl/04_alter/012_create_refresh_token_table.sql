-- ============================================================
-- Refresh token persistence.
-- ============================================================

CREATE TABLE IF NOT EXISTS auth.refresh_token (
    id_refresh_token       UUID        NOT NULL DEFAULT gen_random_uuid(),
    id_user                UUID        NOT NULL,
    token_hash             TEXT        NOT NULL,
    family_id              UUID        NOT NULL DEFAULT gen_random_uuid(),
    session_version        INTEGER     NOT NULL,
    expires_at             TIMESTAMPTZ NOT NULL,
    revoked_at             TIMESTAMPTZ NULL,
    replaced_by_token_hash TEXT        NULL,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at           TIMESTAMPTZ NULL,

    CONSTRAINT pk_refresh_token
        PRIMARY KEY (id_refresh_token),

    CONSTRAINT uq_refresh_token_hash
        UNIQUE (token_hash),

    CONSTRAINT ck_refresh_token_session_version
        CHECK (session_version >= 0),

    CONSTRAINT ck_refresh_token_expiry
        CHECK (expires_at > created_at),

    CONSTRAINT ck_refresh_token_revoked_at
        CHECK (
            revoked_at IS NULL
            OR revoked_at >= created_at
        )
);

ALTER TABLE auth.refresh_token
DROP CONSTRAINT IF EXISTS fk_refresh_token_user;

ALTER TABLE auth.refresh_token
ADD CONSTRAINT fk_refresh_token_user
FOREIGN KEY (id_user)
REFERENCES auth."user"(id_user);

CREATE INDEX IF NOT EXISTS idx_refresh_token_user
ON auth.refresh_token (id_user);

CREATE INDEX IF NOT EXISTS idx_refresh_token_family
ON auth.refresh_token (family_id);

CREATE INDEX IF NOT EXISTS idx_refresh_token_active
ON auth.refresh_token (id_user, expires_at)
WHERE revoked_at IS NULL;