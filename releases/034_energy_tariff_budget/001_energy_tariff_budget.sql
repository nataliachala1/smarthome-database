-- SQL034 | SmartHome | COP/kWh tariff and monthly goals per home
-- ADDITIVE migration. Does not modify previous changesets or consumption data.
-- Tariff effective from a local date (America/Bogota); use the latest
-- effective_from <= consumption date to compute estimates.
-- Stores no computed amounts and does not modify previous readings.

CREATE TABLE config.home_energy_tariff (
  id_home_energy_tariff UUID NOT NULL DEFAULT gen_random_uuid(),
  id_home UUID NOT NULL,
  unit_price_cop_kwh NUMERIC(14,4) NOT NULL,
  effective_from DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_home_energy_tariff PRIMARY KEY (id_home_energy_tariff),
  CONSTRAINT fk_home_energy_tariff_home FOREIGN KEY (id_home)
    REFERENCES homes.home(id_home) ON DELETE RESTRICT,
  CONSTRAINT uq_home_energy_tariff_effective UNIQUE (id_home, effective_from),
  CONSTRAINT ck_home_energy_tariff_positive CHECK (unit_price_cop_kwh > 0)
);

COMMENT ON TABLE config.home_energy_tariff IS
  'Tarifa referencial COP por kWh del hogar; cada nueva vigencia se inserta como una nueva fila.';
COMMENT ON COLUMN config.home_energy_tariff.effective_from IS
  'Fecha de entrada en vigor segun el calendario local America/Bogota. No incluye cargos fijos ni impuestos.';

CREATE TABLE config.home_energy_goal (
  id_home_energy_goal UUID NOT NULL DEFAULT gen_random_uuid(),
  id_home UUID NOT NULL,
  month_start DATE NOT NULL,
  monthly_budget_cop NUMERIC(14,2) NOT NULL,
  target_kwh NUMERIC(14,6) NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_home_energy_goal PRIMARY KEY (id_home_energy_goal),
  CONSTRAINT fk_home_energy_goal_home FOREIGN KEY (id_home)
    REFERENCES homes.home(id_home) ON DELETE RESTRICT,
  CONSTRAINT uq_home_energy_goal_month UNIQUE (id_home, month_start),
  CONSTRAINT ck_home_energy_goal_month_first CHECK (EXTRACT(DAY FROM month_start) = 1),
  CONSTRAINT ck_home_energy_goal_budget_positive CHECK (monthly_budget_cop > 0),
  CONSTRAINT ck_home_energy_goal_target_positive CHECK (target_kwh IS NULL OR target_kwh > 0)
);

CREATE TRIGGER trg_home_energy_goal_updated_at
BEFORE UPDATE ON config.home_energy_goal
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

COMMENT ON TABLE config.home_energy_goal IS
  'Presupuesto de costo estimado y meta maxima de kWh de un hogar para un mes calendario.';
COMMENT ON COLUMN config.home_energy_goal.target_kwh IS
  'Limite objetivo de consumo del mes en kWh; NULL significa que no se configuro meta energetica.';

-- Do not allow access through PUBLIC or the ingest/worker roles.
REVOKE ALL ON TABLE config.home_energy_tariff, config.home_energy_goal FROM PUBLIC;

-- Application: access under RLS; only the owner writes; an authorized MEMBER reads.
GRANT SELECT, INSERT ON TABLE config.home_energy_tariff TO smarthome_runtime_app;
GRANT SELECT, INSERT ON TABLE config.home_energy_goal TO smarthome_runtime_app;
GRANT UPDATE (monthly_budget_cop, target_kwh)
  ON TABLE config.home_energy_goal TO smarthome_runtime_app;

-- Technical administrative role, never used as the regular NestJS LOGIN.
GRANT SELECT, INSERT, UPDATE ON TABLE
  config.home_energy_tariff, config.home_energy_goal TO smarthome_admin;

ALTER TABLE config.home_energy_tariff ENABLE ROW LEVEL SECURITY;
ALTER TABLE config.home_energy_goal ENABLE ROW LEVEL SECURITY;

-- The helper already restricts consumption detail to an OWNER or an authorized
-- active MEMBER. A GUEST does not automatically get tariffs/budgets.
CREATE POLICY home_energy_tariff_select_policy
ON config.home_energy_tariff FOR SELECT TO smarthome_runtime_app
USING (consumption.fn_can_read_detail(id_home));

CREATE POLICY home_energy_tariff_insert_policy
ON config.home_energy_tariff FOR INSERT TO smarthome_runtime_app
WITH CHECK (homes.fn_can_manage_home(id_home));

CREATE POLICY home_energy_goal_select_policy
ON config.home_energy_goal FOR SELECT TO smarthome_runtime_app
USING (consumption.fn_can_read_detail(id_home));

CREATE POLICY home_energy_goal_insert_policy
ON config.home_energy_goal FOR INSERT TO smarthome_runtime_app
WITH CHECK (homes.fn_can_manage_home(id_home));

CREATE POLICY home_energy_goal_update_policy
ON config.home_energy_goal FOR UPDATE TO smarthome_runtime_app
USING (homes.fn_can_manage_home(id_home))
WITH CHECK (homes.fn_can_manage_home(id_home));

-- No DELETE policy and no UPDATE permission on tariffs: immutable history.
-- To change a tariff, add a new effective period (INSERT).
