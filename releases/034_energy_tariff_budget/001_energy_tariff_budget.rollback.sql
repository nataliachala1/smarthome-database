-- Roll back only when NO user configurations exist.
-- Prevents deleting real budgets and tariffs by accident.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM config.home_energy_goal)
     OR EXISTS (SELECT 1 FROM config.home_energy_tariff) THEN
    RAISE EXCEPTION USING ERRCODE='55000',
      MESSAGE='SQL034_ROLLBACK_BLOCKED_NONEMPTY_ENERGY_CONFIGURATION';
  END IF;
END;
$$;

DROP TABLE config.home_energy_goal;
DROP TABLE config.home_energy_tariff;
