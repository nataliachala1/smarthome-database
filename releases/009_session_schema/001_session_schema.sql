-- Bridge the Prisma session contract missing from the original Liquibase history.
-- Preserve compatible installations where these objects were provisioned manually.
ALTER TABLE auth."user" ADD COLUMN IF NOT EXISTS session_version INTEGER NOT NULL DEFAULT 0;
CREATE TABLE IF NOT EXISTS auth.refresh_token (
  id_refresh_token UUID CONSTRAINT pk_refresh_token PRIMARY KEY DEFAULT gen_random_uuid(),
  id_user UUID NOT NULL CONSTRAINT fk_refresh_token_user REFERENCES auth."user"(id_user) ON DELETE NO ACTION ON UPDATE NO ACTION,
  token_hash TEXT NOT NULL,
  family_id UUID NOT NULL DEFAULT gen_random_uuid(),
  session_version INTEGER NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  replaced_by_token_hash TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at TIMESTAMPTZ
);

DO $$ BEGIN
  IF EXISTS (
    SELECT * FROM (VALUES
      ('id_refresh_token','uuid','NO'), ('id_user','uuid','NO'), ('token_hash','text','NO'),
      ('family_id','uuid','NO'), ('session_version','integer','NO'),
      ('expires_at','timestamp with time zone','NO'), ('revoked_at','timestamp with time zone','YES'),
      ('replaced_by_token_hash','text','YES'), ('created_at','timestamp with time zone','NO'),
      ('last_used_at','timestamp with time zone','YES')
    ) expected(column_name,data_type,is_nullable)
    EXCEPT SELECT column_name::text,data_type::text,is_nullable::text FROM information_schema.columns
      WHERE table_schema='auth' AND table_name='refresh_token'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns WHERE table_schema='auth' AND table_name='user'
      AND column_name='session_version' AND data_type='integer' AND is_nullable='NO'
  ) THEN
    RAISE EXCEPTION 'Session schema differs from the expected contract; reconcile before migration';
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_refresh_token_hash ON auth.refresh_token(token_hash);
CREATE INDEX IF NOT EXISTS idx_refresh_token_user ON auth.refresh_token(id_user);
CREATE INDEX IF NOT EXISTS idx_refresh_token_family ON auth.refresh_token(family_id);
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attname='id_refresh_token'
    WHERE c.conrelid='auth.refresh_token'::regclass AND c.contype='p' AND c.conkey=ARRAY[a.attnum]
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_constraint c JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attname='id_user'
    JOIN pg_attribute target ON target.attrelid=c.confrelid AND target.attname='id_user'
    WHERE c.conrelid='auth.refresh_token'::regclass AND c.contype='f' AND c.conkey=ARRAY[a.attnum]
      AND c.confrelid='auth.user'::regclass AND c.confkey=ARRAY[target.attnum]
      AND c.confdeltype='a' AND c.confupdtype='a' AND c.convalidated
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attname='token_hash'
    WHERE i.indrelid='auth.refresh_token'::regclass AND i.indisunique AND i.indisvalid
      AND i.indkey::text=a.attnum::text AND i.indpred IS NULL
  ) THEN
    RAISE EXCEPTION 'Session keys or constraints differ from the expected contract; reconcile before migration';
  END IF;
END $$;
GRANT SELECT ON auth.refresh_token TO smarthome_runtime_app, smarthome_admin;
GRANT INSERT (id_user,token_hash,family_id,session_version,expires_at) ON auth.refresh_token TO smarthome_runtime_app;
GRANT UPDATE (revoked_at,replaced_by_token_hash,last_used_at) ON auth.refresh_token TO smarthome_runtime_app;
GRANT INSERT,UPDATE ON auth.refresh_token TO smarthome_admin;
GRANT UPDATE (session_version,updated_at) ON auth."user" TO smarthome_runtime_app;
