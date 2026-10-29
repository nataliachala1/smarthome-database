-- SQL034 | SmartHome | tarifa COP/kWh y objetivos mensuales por hogar
-- Migracion ADITIVA. No modifica changesets previos ni datos de consumo.
-- Tarifa efectiva desde fecha local (America/Bogota); usar la ultima
-- effective_from <= fecha del consumo para calcular estimaciones.
-- No almacena importes calculados ni modifica lecturas previas.

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

-- No permitir acceso por PUBLIC ni por los roles de ingesta/worker.
REVOKE ALL ON TABLE config.home_energy_tariff, config.home_energy_goal FROM PUBLIC;

-- Aplicacion: acceso bajo RLS; solo owner escribe; MEMBER autorizado consulta.
GRANT SELECT, INSERT ON TABLE config.home_energy_tariff TO smarthome_runtime_app;
GRANT SELECT, INSERT ON TABLE config.home_energy_goal TO smarthome_runtime_app;
GRANT UPDATE (monthly_budget_cop, target_kwh)
  ON TABLE config.home_energy_goal TO smarthome_runtime_app;

-- Rol administrativo tecnico, nunca utilizado como LOGIN habitual de NestJS.
GRANT SELECT, INSERT, UPDATE ON TABLE
  config.home_energy_tariff, config.home_energy_goal TO smarthome_admin;

ALTER TABLE config.home_energy_tariff ENABLE ROW LEVEL SECURITY;
ALTER TABLE config.home_energy_goal ENABLE ROW LEVEL SECURITY;

-- El helper ya restringe detalle de consumo a OWNER o MEMBER activo
-- autorizado. GUEST no obtiene automaticamente tarifas/presupuestos.
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

-- Sin policy DELETE ni permisos UPDATE de tarifas: historico inmutable.
-- Para cambios de tarifa agregar nueva vigencia (INSERT).
