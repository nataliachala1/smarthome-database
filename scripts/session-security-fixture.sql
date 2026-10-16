-- Synthetic fixture for a NEW disposable database named smarthome_session_test only.
-- This is not a Liquibase changeset or a migration for an installed database.
DO $$ BEGIN
  IF current_database() <> 'smarthome_session_test' THEN
    RAISE EXCEPTION 'The session fixture requires its disposable test database';
  END IF;
END $$;
CREATE SCHEMA auth;
CREATE TABLE auth."user" (id_user uuid PRIMARY KEY);
CREATE TABLE auth.refresh_token (
  id_refresh_token uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  id_user uuid NOT NULL REFERENCES auth."user"(id_user),
  token_hash text NOT NULL UNIQUE,
  family_id uuid NOT NULL DEFAULT gen_random_uuid(),
  session_version integer NOT NULL,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  replaced_by_token_hash text,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz
);
CREATE INDEX idx_refresh_token_family ON auth.refresh_token(family_id);
CREATE INDEX idx_refresh_token_user ON auth.refresh_token(id_user);
