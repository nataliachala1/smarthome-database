\set ON_ERROR_STOP on
\echo 'SQL034 | bateria completa de RLS, restricciones, permisos y revocacion'
\echo 'No deja datos persistentes: BEGIN ... ROLLBACK'

BEGIN;

-- Cada identificador es efimero y exclusivo para esta ejecucion.
SELECT gen_random_uuid() AS owner_id,
       gen_random_uuid() AS member_id,
       gen_random_uuid() AS guest_id,
       gen_random_uuid() AS outsider_id,
       gen_random_uuid() AS home_id \gset

-- Preparar identidades funcionales con el usuario administrativo local.
INSERT INTO auth."user" (id_user, id_role, name, email, password_hash, status, email_verified)
SELECT :'owner_id'::uuid, id_role, 'SQL034 OWNER', :'owner_id' || '@sql034.example.invalid',
       'INACTIVE_TEST_HASH_ONLY', 'ACTIVE', TRUE
FROM auth.role WHERE name = 'USER';
INSERT INTO auth."user" (id_user, id_role, name, email, password_hash, status, email_verified)
SELECT :'member_id'::uuid, id_role, 'SQL034 MEMBER', :'member_id' || '@sql034.example.invalid',
       'INACTIVE_TEST_HASH_ONLY', 'ACTIVE', TRUE
FROM auth.role WHERE name = 'USER';
INSERT INTO auth."user" (id_user, id_role, name, email, password_hash, status, email_verified)
SELECT :'guest_id'::uuid, id_role, 'SQL034 GUEST', :'guest_id' || '@sql034.example.invalid',
       'INACTIVE_TEST_HASH_ONLY', 'ACTIVE', TRUE
FROM auth.role WHERE name = 'USER';
INSERT INTO auth."user" (id_user, id_role, name, email, password_hash, status, email_verified)
SELECT :'outsider_id'::uuid, id_role, 'SQL034 OUTSIDER', :'outsider_id' || '@sql034.example.invalid',
       'INACTIVE_TEST_HASH_ONLY', 'ACTIVE', TRUE
FROM auth.role WHERE name = 'USER';

-- Si faltara el rol USER, estas FK fallan: no continuar con un fixture incompleto.
INSERT INTO homes.home (id_home, created_by, name, status)
VALUES (:'home_id'::uuid, :'owner_id'::uuid, 'SQL034 RLS isolated test home', 'ACTIVE');

INSERT INTO homes.home_member
  (id_home, id_user, role, status, accepted_at, invited_by)
VALUES
  (:'home_id'::uuid, :'owner_id'::uuid, 'OWNER', 'ACTIVE', now(), NULL),
  (:'home_id'::uuid, :'member_id'::uuid, 'MEMBER', 'ACTIVE', now(), :'owner_id'::uuid),
  (:'home_id'::uuid, :'guest_id'::uuid, 'GUEST', 'ACTIVE', now(), :'owner_id'::uuid);

-- Contexto de prueba guardado solo dentro de esta transaccion.
SELECT set_config('app.sql034_test_home_id', :'home_id', true);

-- IMPORTANTISIMO: validar RLS con el rol normal, nunca con superusuario.
SET LOCAL ROLE smarthome_runtime_app;
SELECT current_user AS role_bajo_prueba, current_setting('row_security') AS rls_setting;

-- OWNER: puede insertar, leer y actualizar el presupuesto.
SELECT set_config('app.current_user_id', :'owner_id', true);
INSERT INTO config.home_energy_tariff (id_home, unit_price_cop_kwh, effective_from)
VALUES (current_setting('app.sql034_test_home_id')::uuid, 850.2500, DATE '2026-10-01');
INSERT INTO config.home_energy_goal (id_home, month_start, monthly_budget_cop, target_kwh)
VALUES (current_setting('app.sql034_test_home_id')::uuid, DATE '2026-10-01', 120000.00, 150.000000);
UPDATE config.home_energy_goal
SET monthly_budget_cop = 130000.00, target_kwh = 140.000000
WHERE id_home = current_setting('app.sql034_test_home_id')::uuid;
DO $$
BEGIN
  IF (SELECT COUNT(*) FROM config.home_energy_tariff) <> 1 OR
     (SELECT COUNT(*) FROM config.home_energy_goal
        WHERE monthly_budget_cop = 130000.00 AND target_kwh = 140.000000) <> 1 THEN
    RAISE EXCEPTION 'SQL034_OWNER_READ_OR_UPDATE_FAILED';
  END IF;
END;
$$;
\echo 'PASS: OWNER puede insertar, leer y actualizar presupuesto'

-- OWNER: constraints positivos y primer dia del mes.
DO $$
DECLARE v_denied boolean;
BEGIN
  v_denied := false;
  BEGIN
    INSERT INTO config.home_energy_tariff (id_home, unit_price_cop_kwh, effective_from)
    VALUES (current_setting('app.sql034_test_home_id')::uuid, -1, DATE '2026-12-01');
  EXCEPTION WHEN check_violation THEN v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'SQL034_INVALID_TARIFF_ACCEPTED'; END IF;

  v_denied := false;
  BEGIN
    INSERT INTO config.home_energy_goal (id_home, month_start, monthly_budget_cop)
    VALUES (current_setting('app.sql034_test_home_id')::uuid, DATE '2026-11-01', 0);
  EXCEPTION WHEN check_violation THEN v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'SQL034_INVALID_BUDGET_ACCEPTED'; END IF;

  v_denied := false;
  BEGIN
    INSERT INTO config.home_energy_goal (id_home, month_start, monthly_budget_cop)
    VALUES (current_setting('app.sql034_test_home_id')::uuid, DATE '2026-11-15', 10000);
  EXCEPTION WHEN check_violation THEN v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'SQL034_INVALID_MONTH_ACCEPTED'; END IF;

  v_denied := false;
  BEGIN
    INSERT INTO config.home_energy_tariff (id_home, unit_price_cop_kwh, effective_from)
    VALUES (current_setting('app.sql034_test_home_id')::uuid, 920, DATE '2026-10-01');
  EXCEPTION WHEN unique_violation THEN v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'SQL034_DUPLICATE_TARIFF_ACCEPTED'; END IF;
END;
$$;
\echo 'PASS: CHECK y UNIQUE rechazan entradas invalidas'

-- MEMBER activo con permiso por defecto: puede leer, no insertar.
SELECT set_config('app.current_user_id', :'member_id', true);
DO $$
DECLARE v_denied boolean := false;
BEGIN
  IF (SELECT COUNT(*) FROM config.home_energy_tariff) <> 1 OR
     (SELECT COUNT(*) FROM config.home_energy_goal) <> 1 THEN
    RAISE EXCEPTION 'SQL034_MEMBER_EXPECTED_READ_FAILED';
  END IF;
  BEGIN
    INSERT INTO config.home_energy_tariff (id_home, unit_price_cop_kwh, effective_from)
    VALUES (current_setting('app.sql034_test_home_id')::uuid, 925, DATE '2026-12-01');
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'SQL034_MEMBER_WRITE_WAS_ALLOWED'; END IF;
END;
$$;
\echo 'PASS: MEMBER autorizado lee ambas tablas, no inserta tarifa'

-- GUEST activo: no puede leer configuraciones energeticas.
SELECT set_config('app.current_user_id', :'guest_id', true);
DO $$
BEGIN
  IF (SELECT COUNT(*) FROM config.home_energy_tariff) <> 0 OR
     (SELECT COUNT(*) FROM config.home_energy_goal) <> 0 THEN
    RAISE EXCEPTION 'SQL034_GUEST_READ_WAS_ALLOWED';
  END IF;
END;
$$;
\echo 'PASS: GUEST no lee configuraciones energeticas'

-- Usuario externo al hogar: no puede leer ni escribir.
SELECT set_config('app.current_user_id', :'outsider_id', true);
DO $$
DECLARE v_denied boolean := false;
BEGIN
  IF (SELECT COUNT(*) FROM config.home_energy_tariff) <> 0 OR
     (SELECT COUNT(*) FROM config.home_energy_goal) <> 0 THEN
    RAISE EXCEPTION 'SQL034_OUTSIDER_READ_WAS_ALLOWED';
  END IF;
  BEGIN
    INSERT INTO config.home_energy_goal (id_home, month_start, monthly_budget_cop)
    VALUES (current_setting('app.sql034_test_home_id')::uuid, DATE '2026-12-01', 30000);
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'SQL034_OUTSIDER_WRITE_WAS_ALLOWED'; END IF;
END;
$$;
\echo 'PASS: usuario externo no lee ni escribe'

-- El rol de aplicacion no puede cambiar claves de identidad por UPDATE.
DO $$
BEGIN
  IF has_column_privilege('smarthome_runtime_app', 'config.home_energy_goal', 'id_home', 'UPDATE') OR
     has_column_privilege('smarthome_runtime_app', 'config.home_energy_goal', 'month_start', 'UPDATE') OR
     NOT has_column_privilege('smarthome_runtime_app', 'config.home_energy_goal', 'monthly_budget_cop', 'UPDATE') THEN
    RAISE EXCEPTION 'SQL034_COLUMN_PRIVILEGES_INVALID';
  END IF;
END;
$$;
\echo 'PASS: columnas id_home y month_start no son modificables por runtime'

-- SQL034: pruebas complementarias de permiso de consumo y revocacion.
-- Se reutilizan los usuarios y el hogar temporales del mismo BEGIN.

-- Recuperar la membresia exacta: fn_set_member_permissions recibe id_home_member.
-- El rol de aplicacion continua activo; OWNER puede consultar a sus miembros.
SELECT set_config('app.current_user_id', :'owner_id', true);
SELECT set_config(
  'app.sql034_test_member_membership_id',
  (
    SELECT hm.id_home_member::text
    FROM homes.home_member AS hm
    WHERE hm.id_home = current_setting('app.sql034_test_home_id')::uuid
      AND hm.id_user = :'member_id'::uuid
      AND hm.role = 'MEMBER'
      AND hm.status = 'ACTIVE'
  ),
  true
);

-- El OWNER retira unicamente view_consumption usando la funcion publica
-- autorizada, no mediante UPDATE directo a una tabla protegida.
DO $$
BEGIN
  IF NOT homes.fn_set_member_permissions(
      current_setting('app.sql034_test_home_id')::uuid,
      current_setting('app.sql034_test_member_membership_id')::uuid,
      TRUE, FALSE, TRUE
  ) THEN
    RAISE EXCEPTION 'SQL034_PERMISSION_DISABLE_FAILED';
  END IF;
END;
$$;

-- MEMBER sigue siendo ACTIVE pero pierde acceso a tarifas y metas.
SELECT set_config('app.current_user_id', :'member_id', true);
DO $$
BEGIN
  IF (SELECT COUNT(*) FROM config.home_energy_tariff
      WHERE id_home = current_setting('app.sql034_test_home_id')::uuid) <> 0
     OR (SELECT COUNT(*) FROM config.home_energy_goal
      WHERE id_home = current_setting('app.sql034_test_home_id')::uuid) <> 0 THEN
    RAISE EXCEPTION 'SQL034_MEMBER_WITHOUT_CONSUMPTION_PERMISSION_READ_DATA';
  END IF;
END;
$$;
\echo 'PASS: MEMBER sin view_consumption no puede leer tarifas ni presupuestos'

-- Reponer el permiso dentro de la transaccion; debe restaurar la lectura.
SELECT set_config('app.current_user_id', :'owner_id', true);
DO $$
BEGIN
  IF NOT homes.fn_set_member_permissions(
      current_setting('app.sql034_test_home_id')::uuid,
      current_setting('app.sql034_test_member_membership_id')::uuid,
      TRUE, TRUE, TRUE
  ) THEN
    RAISE EXCEPTION 'SQL034_PERMISSION_RESTORE_FAILED';
  END IF;
END;
$$;
SELECT set_config('app.current_user_id', :'member_id', true);
DO $$
BEGIN
  IF (SELECT COUNT(*) FROM config.home_energy_tariff
      WHERE id_home = current_setting('app.sql034_test_home_id')::uuid) <> 1
     OR (SELECT COUNT(*) FROM config.home_energy_goal
      WHERE id_home = current_setting('app.sql034_test_home_id')::uuid) <> 1 THEN
    RAISE EXCEPTION 'SQL034_MEMBER_RESTORED_PERMISSION_NOT_HONORED';
  END IF;
END;
$$;
\echo 'PASS: MEMBER recupera lectura al restaurarse view_consumption'

-- El OWNER revoca la membresia por el flujo protegido de homes.home_member.
SELECT set_config('app.current_user_id', :'owner_id', true);
DO $$
DECLARE v_rows INTEGER;
BEGIN
  UPDATE homes.home_member
     SET status = 'REVOKED', ended_at = NOW()
   WHERE id_home_member = current_setting('app.sql034_test_member_membership_id')::uuid
     AND id_home = current_setting('app.sql034_test_home_id')::uuid
     AND role = 'MEMBER' AND status = 'ACTIVE';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'SQL034_MEMBER_REVOCATION_FAILED: %', v_rows;
  END IF;
END;
$$;

-- Incluso con permiso view_consumption = TRUE en la tabla de permisos,
-- una membresia REVOKED no puede consultar informacion economica.
SELECT set_config('app.current_user_id', :'member_id', true);
DO $$
BEGIN
  IF (SELECT COUNT(*) FROM config.home_energy_tariff
      WHERE id_home = current_setting('app.sql034_test_home_id')::uuid) <> 0
     OR (SELECT COUNT(*) FROM config.home_energy_goal
      WHERE id_home = current_setting('app.sql034_test_home_id')::uuid) <> 0 THEN
    RAISE EXCEPTION 'SQL034_REVOKED_MEMBER_CAN_READ';
  END IF;
END;
$$;
\echo 'PASS: membresia REVOKED bloquea la lectura de tarifas y presupuestos'

-- Todas las inserciones y cambios de prueba se revierten.
ROLLBACK;
\echo 'EXITO: pruebas SQL034 completas, transaccion revertida; sin datos de prueba persistentes.'
