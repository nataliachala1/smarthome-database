\set ON_ERROR_STOP on
\echo 'SQL034 | budget/goal optionality tests: one of two fields must be set'
\echo 'Local-only fixture. All changes rolled back.'
BEGIN;

SELECT gen_random_uuid() AS owner_id,
       gen_random_uuid() AS member_id,
       gen_random_uuid() AS guest_id,
       gen_random_uuid() AS home_id \gset

INSERT INTO auth."user" (id_user, id_role, name, email, password_hash, status, email_verified)
SELECT :'owner_id'::uuid, id_role, 'SQL034 OWNER budget',
       :'owner_id' || '@sql034.example.invalid', 'TEST_ONLY_NOT_REAL_HASH', 'ACTIVE', TRUE
FROM auth.role WHERE name = 'USER';
INSERT INTO auth."user" (id_user, id_role, name, email, password_hash, status, email_verified)
SELECT :'member_id'::uuid, id_role, 'SQL034 MEMBER budget',
       :'member_id' || '@sql034.example.invalid', 'TEST_ONLY_NOT_REAL_HASH', 'ACTIVE', TRUE
FROM auth.role WHERE name = 'USER';
INSERT INTO auth."user" (id_user, id_role, name, email, password_hash, status, email_verified)
SELECT :'guest_id'::uuid, id_role, 'SQL034 GUEST budget',
       :'guest_id' || '@sql034.example.invalid', 'TEST_ONLY_NOT_REAL_HASH', 'ACTIVE', TRUE
FROM auth.role WHERE name = 'USER';

INSERT INTO homes.home (id_home, created_by, name, status)
VALUES (:'home_id'::uuid, :'owner_id'::uuid, 'SQL034 Optional Budget Test', 'ACTIVE');

INSERT INTO homes.home_member (id_home, id_user, role, status, accepted_at, invited_by)
VALUES (:'home_id'::uuid, :'owner_id'::uuid, 'OWNER', 'ACTIVE', now(), NULL),
       (:'home_id'::uuid, :'member_id'::uuid, 'MEMBER', 'ACTIVE', now(), :'owner_id'::uuid),
       (:'home_id'::uuid, :'guest_id'::uuid, 'GUEST', 'ACTIVE', now(), :'owner_id'::uuid);

SELECT set_config('app.sql034_test_home_id', :'home_id', true);
SET LOCAL ROLE smarthome_runtime_app;
SELECT set_config('app.current_user_id', :'owner_id', true);

-- 1: Only energy goal (no monetary budget).
INSERT INTO config.home_energy_goal (id_home, month_start, target_kwh)
VALUES (current_setting('app.sql034_test_home_id')::uuid, DATE '2026-11-01', 130.000000);
-- 2: Only monetary budget (no energy goal).
INSERT INTO config.home_energy_goal (id_home, month_start, monthly_budget_cop)
VALUES (current_setting('app.sql034_test_home_id')::uuid, DATE '2026-12-01', 100000.00);
-- 3: Both values.
INSERT INTO config.home_energy_goal (id_home, month_start, monthly_budget_cop, target_kwh)
VALUES (current_setting('app.sql034_test_home_id')::uuid, DATE '2027-01-01', 120000.00, 140.000000);

DO $$
BEGIN
  IF (SELECT count(*) FROM config.home_energy_goal) <> 3
     OR NOT EXISTS (SELECT 1 FROM config.home_energy_goal
                    WHERE month_start = DATE '2026-11-01'
                      AND monthly_budget_cop IS NULL AND target_kwh = 130)
     OR NOT EXISTS (SELECT 1 FROM config.home_energy_goal
                    WHERE month_start = DATE '2026-12-01'
                      AND monthly_budget_cop = 100000 AND target_kwh IS NULL)
     OR NOT EXISTS (SELECT 1 FROM config.home_energy_goal
                    WHERE month_start = DATE '2027-01-01'
                      AND monthly_budget_cop = 120000 AND target_kwh = 140)
  THEN
    RAISE EXCEPTION 'FAIL: expected 3 valid optional-budget configurations';
  END IF;
END $$;
\echo 'PASS: OWNER can store kWh-only, COP-only and combined configurations'

-- UPDATE can remove COP budget if a kWh goal remains.
UPDATE config.home_energy_goal
SET monthly_budget_cop = 25000.00
WHERE id_home = current_setting('app.sql034_test_home_id')::uuid
  AND month_start = DATE '2026-11-01';
UPDATE config.home_energy_goal
SET monthly_budget_cop = NULL
WHERE id_home = current_setting('app.sql034_test_home_id')::uuid
  AND month_start = DATE '2026-11-01';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM config.home_energy_goal
                 WHERE month_start = DATE '2026-11-01'
                   AND monthly_budget_cop IS NULL AND target_kwh = 130) THEN
    RAISE EXCEPTION 'FAIL: budget NULL update not persisted';
  END IF;
END $$;
\echo 'PASS: OWNER can clear the COP budget while retaining kWh goal'

DO $$
DECLARE v_rejected boolean;
BEGIN
  -- No budget and no goal is invalid.
  v_rejected := false;
  BEGIN
    INSERT INTO config.home_energy_goal (id_home, month_start, monthly_budget_cop, target_kwh)
    VALUES (current_setting('app.sql034_test_home_id')::uuid, DATE '2027-02-01', NULL, NULL);
  EXCEPTION WHEN check_violation THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'FAIL: both NULL accepted'; END IF;

  -- Explicit zero budget remains invalid.
  v_rejected := false;
  BEGIN
    INSERT INTO config.home_energy_goal (id_home, month_start, monthly_budget_cop)
    VALUES (current_setting('app.sql034_test_home_id')::uuid, DATE '2027-02-01', 0);
  EXCEPTION WHEN check_violation THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'FAIL: zero budget accepted'; END IF;

  -- Explicit zero or negative kWh target remains invalid.
  v_rejected := false;
  BEGIN
    INSERT INTO config.home_energy_goal (id_home, month_start, target_kwh)
    VALUES (current_setting('app.sql034_test_home_id')::uuid, DATE '2027-02-01', 0);
  EXCEPTION WHEN check_violation THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'FAIL: zero target accepted'; END IF;

  v_rejected := false;
  BEGIN
    INSERT INTO config.home_energy_goal (id_home, month_start, target_kwh)
    VALUES (current_setting('app.sql034_test_home_id')::uuid, DATE '2027-02-01', -10);
  EXCEPTION WHEN check_violation THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'FAIL: negative target accepted'; END IF;

  -- Existing unique(month,home) remains enforced.
  v_rejected := false;
  BEGIN
    INSERT INTO config.home_energy_goal (id_home, month_start, target_kwh)
    VALUES (current_setting('app.sql034_test_home_id')::uuid, DATE '2026-11-01', 200);
  EXCEPTION WHEN unique_violation THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'FAIL: duplicate month accepted'; END IF;
END $$;
\echo 'PASS: cannot store empty, zero, negative, or duplicate monthly configurations'

SELECT set_config('app.current_user_id', :'member_id', true);
DO $$
DECLARE v_rejected boolean := false;
BEGIN
  IF (SELECT count(*) FROM config.home_energy_goal) <> 3 THEN
    RAISE EXCEPTION 'FAIL: authorized MEMBER cannot read configurations';
  END IF;
  BEGIN
    INSERT INTO config.home_energy_goal (id_home, month_start, target_kwh)
    VALUES (current_setting('app.sql034_test_home_id')::uuid, DATE '2027-03-01', 100);
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'FAIL: MEMBER can insert goal'; END IF;
END $$;
\echo 'PASS: MEMBER reads but cannot create a goal'

SELECT set_config('app.current_user_id', :'guest_id', true);
DO $$
BEGIN
  IF (SELECT count(*) FROM config.home_energy_goal) <> 0 THEN
    RAISE EXCEPTION 'FAIL: GUEST can read goal';
  END IF;
END $$;
\echo 'PASS: GUEST cannot read any energy goal'

ROLLBACK;
\echo 'EXITO: SQL034 optional budget tests passed; transaction rolled back'
