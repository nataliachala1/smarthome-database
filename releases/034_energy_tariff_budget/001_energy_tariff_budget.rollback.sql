-- Rollback solo cuando NO existen configuraciones de usuarios.
-- Evita eliminar presupuestos y tarifas reales por accidente.
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
