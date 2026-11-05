-- SQL034 follow-up (additive) | A budget in COP is optional when kWh target is present.
-- Never modify the already-applied 001 changeset or its checksum.
ALTER TABLE config.home_energy_goal
  ALTER COLUMN monthly_budget_cop DROP NOT NULL;

ALTER TABLE config.home_energy_goal
  ADD CONSTRAINT ck_home_energy_goal_budget_or_target
  CHECK (monthly_budget_cop IS NOT NULL OR target_kwh IS NOT NULL);

COMMENT ON COLUMN config.home_energy_goal.monthly_budget_cop IS
  'Optional monthly COP budget; NULL means no money budget was configured. A kWh target is required when NULL.';

COMMENT ON COLUMN config.home_energy_goal.target_kwh IS
  'Optional positive kWh target; at least one of target_kwh and monthly_budget_cop must be set.';
