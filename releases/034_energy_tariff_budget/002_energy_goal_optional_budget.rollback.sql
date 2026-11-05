-- Reverting optional budgets is unsafe if any goal has no COP budget.
-- Abort intentionally rather than silently changing or deleting user data.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM config.home_energy_goal
    WHERE monthly_budget_cop IS NULL
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'SQL034_ROLLBACK_BLOCKED_KWH_ONLY_GOALS_EXIST';
  END IF;
END
$$;

ALTER TABLE config.home_energy_goal
  DROP CONSTRAINT ck_home_energy_goal_budget_or_target;

ALTER TABLE config.home_energy_goal
  ALTER COLUMN monthly_budget_cop SET NOT NULL;

COMMENT ON COLUMN config.home_energy_goal.monthly_budget_cop IS NULL;
COMMENT ON COLUMN config.home_energy_goal.target_kwh IS
  'Limite objetivo de consumo del mes en kWh; NULL significa que no se configuro meta energetica.';
