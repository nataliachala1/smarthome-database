-- ============================================================
-- DEMO DATA: test users, home, memberships and device
-- File: 02_dml/90_demo/001_insert_demo_users.sql
-- Purpose: lets an evaluator sign in with every declared role
--          right after a clean installation.
-- Scope: LOCAL and DEMO environments only. It is included from
--        changelog/changelog-demo.yaml and never from
--        changelog/changelog-master.yaml, so production does not
--        receive it.
-- Data: fictitious. Emails use the reserved example.com domain
--       (RFC 2606); no personal data (Ley 1581 de 2012).
-- Password for every account: SmartHome#2026 (Argon2id hash,
--       m=65536, t=3, p=4, same parameters as the backend).
-- ============================================================

INSERT INTO auth."user"
  (id_user, id_role, name, email, password_hash, status, email_verified)
VALUES
  ('d0000000-0000-4000-8000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000001',
   'Demo Admin', 'admin@example.com',
   '$argon2id$v=19$m=65536,t=3,p=4$GxvYqc+7z38ZeccNIVG0rg$0kIh0SqA0NpNpXHbauxj9NVRD1McMHCSUU7bHdvrHks', 'ACTIVE', TRUE),
  ('d0000000-0000-4000-8000-000000000002', 'a1b2c3d4-0001-0000-0000-000000000002',
   'Demo Owner', 'owner@example.com',
   '$argon2id$v=19$m=65536,t=3,p=4$wnYFnK0UeaPF/tx+qFLpNQ$D9XcKwFwCVW4ppz/S+E4NYfgEp5KtRJipT7Qho7ULeA', 'ACTIVE', TRUE),
  ('d0000000-0000-4000-8000-000000000003', 'a1b2c3d4-0001-0000-0000-000000000002',
   'Demo Member', 'member@example.com',
   '$argon2id$v=19$m=65536,t=3,p=4$K4b6evQNa6WBSNtrYW7dGw$gaVe09q/BHM+K9oVcrJn1dLHROdjgMUkRQ/JP0cjYlY', 'ACTIVE', TRUE),
  ('d0000000-0000-4000-8000-000000000004', 'a1b2c3d4-0001-0000-0000-000000000002',
   'Demo Guest', 'guest@example.com',
   '$argon2id$v=19$m=65536,t=3,p=4$6TEgF/7PK08i5k6DU+U1kQ$+PgUUbG0qSpBh4eGTLwxsNcqVAJabYC695b9o/VLarQ', 'ACTIVE', TRUE)
ON CONFLICT (id_user) DO NOTHING;

INSERT INTO homes.home (id_home, created_by, name)
VALUES ('d1000000-0000-4000-8000-000000000001',
        'd0000000-0000-4000-8000-000000000002', 'Casa Demo')
ON CONFLICT (id_home) DO NOTHING;

-- The permission trigger initializes default permissions for each membership.
INSERT INTO homes.home_member
  (id_home_member, id_home, id_user, role, status, invited_by, accepted_at)
VALUES
  ('d2000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000001',
   'd0000000-0000-4000-8000-000000000002', 'OWNER', 'ACTIVE', NULL, NOW()),
  ('d2000000-0000-4000-8000-000000000002', 'd1000000-0000-4000-8000-000000000001',
   'd0000000-0000-4000-8000-000000000003', 'MEMBER', 'ACTIVE',
   'd0000000-0000-4000-8000-000000000002', NOW()),
  ('d2000000-0000-4000-8000-000000000003', 'd1000000-0000-4000-8000-000000000001',
   'd0000000-0000-4000-8000-000000000004', 'GUEST', 'ACTIVE',
   'd0000000-0000-4000-8000-000000000002', NOW())
ON CONFLICT (id_home_member) DO NOTHING;

INSERT INTO devices.device (id_device, id_home, name, transport_type, messaging_protocol)
VALUES ('d3000000-0000-4000-8000-000000000001',
        'd1000000-0000-4000-8000-000000000001', 'Lámpara de la sala', 'WIFI', 'MQTT')
ON CONFLICT (id_device) DO NOTHING;
