-- BD-01B regression audit. Run only on the disposable PostgreSQL lab after
-- Liquibase and synthetic LOGIN fixtures. Read-only assertions; no data changes.
BEGIN TRANSACTION READ ONLY;

DO $bd01$
DECLARE
  r record;
  v_allowed boolean;
  v_actual boolean;
BEGIN
  -- Every LOGIN has one functional NOLOGIN role and no administrative power.
  FOR r IN
    SELECT x.login_name, x.group_name,
           l.oid AS login_oid, l.rolcanlogin, l.rolinherit, l.rolsuper,
           l.rolcreatedb, l.rolcreaterole, l.rolreplication, l.rolbypassrls,
           has_database_privilege(l.rolname, current_database(), 'CREATE') AS database_create,
           has_schema_privilege(l.rolname, 'devices', 'CREATE') AS devices_create,
           has_schema_privilege(l.rolname, 'public', 'CREATE') AS public_create,
           g.rolcanlogin AS group_can_login,
           (SELECT count(*) FROM pg_catalog.pg_auth_members m
             WHERE m.member = l.oid) AS direct_memberships,
           EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members m
             WHERE m.member = l.oid AND m.roleid = g.oid) AS expected_membership
    FROM (VALUES
      ('smarthome_mqtt_reserver_prod_login', 'smarthome_mqtt_reserver'),
      ('smarthome_mqtt_lease_prod_login', 'smarthome_mqtt_lease_worker'),
      ('smarthome_mqtt_confirmer_prod_login', 'smarthome_mqtt_prepare_confirmer'),
      ('smarthome_mqtt_secret_prod_login', 'smarthome_mqtt_secret_worker'),
      ('smarthome_mqtt_rpc_prod_login', 'smarthome_mqtt_rpc_worker'),
      ('smarthome_mqtt_auth_prod_login', 'smarthome_mqtt_auth_confirmer'),
      ('smarthome_mqtt_revoke_prod_login', 'smarthome_mqtt_revoke')
    ) x(login_name, group_name)
    LEFT JOIN pg_catalog.pg_roles l ON l.rolname = x.login_name
    LEFT JOIN pg_catalog.pg_roles g ON g.rolname = x.group_name
  LOOP
    IF r.login_oid IS NULL OR r.group_can_login IS DISTINCT FROM false OR
       r.rolcanlogin IS DISTINCT FROM true OR r.rolinherit IS DISTINCT FROM true OR
       r.rolsuper IS DISTINCT FROM false OR r.rolcreatedb IS DISTINCT FROM false OR
       r.rolcreaterole IS DISTINCT FROM false OR r.rolreplication IS DISTINCT FROM false OR
       r.rolbypassrls IS DISTINCT FROM false OR r.database_create IS DISTINCT FROM false OR
       r.devices_create IS DISTINCT FROM false OR r.public_create IS DISTINCT FROM false OR
       r.direct_memberships <> 1 OR
       r.expected_membership IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'BD01B_ROLE_CONFIGURATION_FAILED: %', r.login_name;
    END IF;
  END LOOP;

  -- The only allowed function set is the exact backend gateway contract.
  FOR r IN
    SELECT l.login_name, l.group_name, a.group_name AS allowed_group,
           a.function_signature,
           to_regprocedure(a.function_signature) AS function_oid
    FROM (VALUES
      ('smarthome_mqtt_reserver_prod_login', 'smarthome_mqtt_reserver'),
      ('smarthome_mqtt_lease_prod_login', 'smarthome_mqtt_lease_worker'),
      ('smarthome_mqtt_confirmer_prod_login', 'smarthome_mqtt_prepare_confirmer'),
      ('smarthome_mqtt_secret_prod_login', 'smarthome_mqtt_secret_worker'),
      ('smarthome_mqtt_rpc_prod_login', 'smarthome_mqtt_rpc_worker'),
      ('smarthome_mqtt_auth_prod_login', 'smarthome_mqtt_auth_confirmer'),
      ('smarthome_mqtt_revoke_prod_login', 'smarthome_mqtt_revoke')
    ) l(login_name, group_name)
    CROSS JOIN (VALUES
      ('smarthome_mqtt_reserver', 'devices.fn_reserve_mqtt_pairing_operation(uuid,text,uuid,text)'),
      ('smarthome_mqtt_lease_worker', 'devices.fn_request_mqtt_enable(uuid,uuid,text)'),
      ('smarthome_mqtt_lease_worker', 'devices.fn_claim_mqtt_enable(uuid,integer)'),
      ('smarthome_mqtt_lease_worker', 'devices.fn_confirm_mqtt_enabled(uuid,uuid,text,text,text)'),
      ('smarthome_mqtt_lease_worker', 'devices.fn_claim_mqtt_pairing_preparation(uuid,integer)'),
      ('smarthome_mqtt_lease_worker', 'devices.fn_report_mqtt_pairing_uncertain(uuid,uuid,text)'),
      ('smarthome_mqtt_prepare_confirmer', 'devices.fn_confirm_mqtt_pairing_prepared(uuid,uuid,uuid,text,text,text)'),
      ('smarthome_mqtt_secret_worker', 'devices.fn_load_mqtt_preparation_secret(uuid,uuid)'),
      ('smarthome_mqtt_secret_worker', 'devices.fn_insert_mqtt_preparation_secret_if_absent(uuid,uuid,smallint,text,text,text,text)'),
      ('smarthome_mqtt_secret_worker', 'devices.fn_get_authorized_mqtt_bootstrap(uuid,uuid,text)'),
      ('smarthome_mqtt_rpc_worker', 'devices.fn_issue_mqtt_rpc_challenge(uuid)'),
      ('smarthome_mqtt_rpc_worker', 'devices.fn_consume_mqtt_rpc_candidate(uuid,uuid)'),
      ('smarthome_mqtt_auth_confirmer', 'devices.fn_confirm_mqtt_broker_authentication(uuid,uuid,text,text,text)'),
      ('smarthome_mqtt_revoke', 'devices.fn_claim_mqtt_pairing_revocation(integer)'),
      ('smarthome_mqtt_revoke', 'devices.fn_finish_mqtt_pairing_revocation(uuid,uuid,text,text)'),
      ('smarthome_mqtt_revoke', 'devices.fn_claim_mqtt_revocation_with_binding()'),
      ('smarthome_mqtt_revoke', 'devices.fn_finish_mqtt_revocation_evidenced(uuid,uuid,text,text)')
    ) a(group_name, function_signature)
  LOOP
    IF r.function_oid IS NULL THEN
      RAISE EXCEPTION 'BD01B_REQUIRED_FUNCTION_MISSING: %', r.function_signature;
    END IF;
    v_allowed := r.group_name = r.allowed_group;
    v_actual := has_function_privilege(r.login_name, r.function_oid, 'EXECUTE');
    IF v_actual IS DISTINCT FROM v_allowed THEN
      RAISE EXCEPTION 'BD01B_FUNCTION_GRANT_MISMATCH: % % expected %, got %',
        r.login_name, r.function_signature, v_allowed, v_actual;
    END IF;
    IF EXISTS (
      SELECT 1 FROM aclexplode(coalesce(
        (SELECT p.proacl FROM pg_catalog.pg_proc p WHERE p.oid = r.function_oid),
        acldefault('f', (SELECT p.proowner FROM pg_catalog.pg_proc p WHERE p.oid = r.function_oid))
      )) a
      WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'BD01B_PUBLIC_FUNCTION_EXECUTE: %', r.function_signature;
    END IF;
  END LOOP;

  -- No extra SECURITY DEFINER/API function may become reachable through a
  -- direct grant, role membership, or PUBLIC execute privilege.
  FOR r IN
    SELECT l.login_name, p.oid::regprocedure AS function_signature
    FROM (VALUES
      ('smarthome_mqtt_reserver_prod_login'),
      ('smarthome_mqtt_lease_prod_login'),
      ('smarthome_mqtt_confirmer_prod_login'),
      ('smarthome_mqtt_secret_prod_login'),
      ('smarthome_mqtt_rpc_prod_login'),
      ('smarthome_mqtt_auth_prod_login'),
      ('smarthome_mqtt_revoke_prod_login')
    ) l(login_name)
    CROSS JOIN pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'devices'
      AND has_function_privilege(l.login_name, p.oid, 'EXECUTE')
      AND NOT EXISTS (
        SELECT 1 FROM (VALUES
          ('smarthome_mqtt_reserver_prod_login', 'devices.fn_reserve_mqtt_pairing_operation(uuid,text,uuid,text)'),
          ('smarthome_mqtt_lease_prod_login', 'devices.fn_request_mqtt_enable(uuid,uuid,text)'),
          ('smarthome_mqtt_lease_prod_login', 'devices.fn_claim_mqtt_enable(uuid,integer)'),
          ('smarthome_mqtt_lease_prod_login', 'devices.fn_confirm_mqtt_enabled(uuid,uuid,text,text,text)'),
          ('smarthome_mqtt_lease_prod_login', 'devices.fn_claim_mqtt_pairing_preparation(uuid,integer)'),
          ('smarthome_mqtt_lease_prod_login', 'devices.fn_report_mqtt_pairing_uncertain(uuid,uuid,text)'),
          ('smarthome_mqtt_confirmer_prod_login', 'devices.fn_confirm_mqtt_pairing_prepared(uuid,uuid,uuid,text,text,text)'),
          ('smarthome_mqtt_secret_prod_login', 'devices.fn_load_mqtt_preparation_secret(uuid,uuid)'),
          ('smarthome_mqtt_secret_prod_login', 'devices.fn_insert_mqtt_preparation_secret_if_absent(uuid,uuid,smallint,text,text,text,text)'),
          ('smarthome_mqtt_secret_prod_login', 'devices.fn_get_authorized_mqtt_bootstrap(uuid,uuid,text)'),
          ('smarthome_mqtt_rpc_prod_login', 'devices.fn_issue_mqtt_rpc_challenge(uuid)'),
          ('smarthome_mqtt_rpc_prod_login', 'devices.fn_consume_mqtt_rpc_candidate(uuid,uuid)'),
          ('smarthome_mqtt_auth_prod_login', 'devices.fn_confirm_mqtt_broker_authentication(uuid,uuid,text,text,text)'),
          ('smarthome_mqtt_revoke_prod_login', 'devices.fn_claim_mqtt_pairing_revocation(integer)'),
          ('smarthome_mqtt_revoke_prod_login', 'devices.fn_finish_mqtt_pairing_revocation(uuid,uuid,text,text)'),
          ('smarthome_mqtt_revoke_prod_login', 'devices.fn_claim_mqtt_revocation_with_binding()'),
          ('smarthome_mqtt_revoke_prod_login', 'devices.fn_finish_mqtt_revocation_evidenced(uuid,uuid,text,text)')
        ) a(login_name, function_signature)
        WHERE a.login_name = l.login_name
          AND a.function_signature = p.oid::regprocedure::text
      )
  LOOP
    RAISE EXCEPTION 'BD01B_UNEXPECTED_FUNCTION_EXECUTE: % %',
      r.login_name, r.function_signature;
  END LOOP;

  -- Legacy and privileged state transitions must be denied to every MQTT login.
  FOR r IN
    SELECT x.login_name, p.function_signature,
           to_regprocedure(p.function_signature) AS function_oid
    FROM (VALUES
      ('smarthome_mqtt_reserver_prod_login'),
      ('smarthome_mqtt_lease_prod_login'),
      ('smarthome_mqtt_confirmer_prod_login'),
      ('smarthome_mqtt_secret_prod_login'),
      ('smarthome_mqtt_rpc_prod_login'),
      ('smarthome_mqtt_auth_prod_login'),
      ('smarthome_mqtt_revoke_prod_login')
    ) x(login_name)
    CROSS JOIN (VALUES
      ('devices.fn_register_mqtt_identity(uuid,uuid,text)'),
      ('devices.fn_claim_mqtt_revocation()'),
      ('devices.fn_finish_mqtt_revocation(uuid,uuid,text)'),
      ('devices.fn_quarantine_expired_mqtt_pairing_lease(uuid)'),
      ('devices.fn_finish_verified_pairing(uuid,uuid)')
    ) p(function_signature)
  LOOP
    IF r.function_oid IS NOT NULL AND
       has_function_privilege(r.login_name, r.function_oid, 'EXECUTE') THEN
      RAISE EXCEPTION 'BD01B_PROHIBITED_FUNCTION_EXECUTE: % %',
        r.login_name, r.function_signature;
    END IF;
  END LOOP;

  -- No direct table/sequence access in application schemas; SECURITY DEFINER
  -- functions are the only approved data path for these service identities.
  FOR r IN
    SELECT l.login_name, c.oid::regclass AS relation_name
    FROM (VALUES
      ('smarthome_mqtt_reserver_prod_login'),
      ('smarthome_mqtt_lease_prod_login'),
      ('smarthome_mqtt_confirmer_prod_login'),
      ('smarthome_mqtt_secret_prod_login'),
      ('smarthome_mqtt_rpc_prod_login'),
      ('smarthome_mqtt_auth_prod_login'),
      ('smarthome_mqtt_revoke_prod_login')
    ) l(login_name)
    CROSS JOIN pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('devices', 'consumption')
      AND c.relkind IN ('r','p','v','m','f')
      AND (has_any_column_privilege(l.login_name, c.oid, 'SELECT') OR
           has_any_column_privilege(l.login_name, c.oid, 'INSERT') OR
           has_any_column_privilege(l.login_name, c.oid, 'UPDATE') OR
           has_table_privilege(l.login_name, c.oid, 'DELETE,TRUNCATE,REFERENCES,TRIGGER'))
  LOOP
    RAISE EXCEPTION 'BD01B_DIRECT_RELATION_PRIVILEGE: % %',
      r.login_name, r.relation_name;
  END LOOP;

  FOR r IN
    SELECT l.login_name, c.oid::regclass AS sequence_name
    FROM (VALUES
      ('smarthome_mqtt_reserver_prod_login'),
      ('smarthome_mqtt_lease_prod_login'),
      ('smarthome_mqtt_confirmer_prod_login'),
      ('smarthome_mqtt_secret_prod_login'),
      ('smarthome_mqtt_rpc_prod_login'),
      ('smarthome_mqtt_auth_prod_login'),
      ('smarthome_mqtt_revoke_prod_login')
    ) l(login_name)
    CROSS JOIN pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('devices', 'consumption') AND c.relkind = 'S'
      AND (has_sequence_privilege(l.login_name, c.oid, 'USAGE') OR
           has_sequence_privilege(l.login_name, c.oid, 'SELECT') OR
           has_sequence_privilege(l.login_name, c.oid, 'UPDATE'))
  LOOP
    RAISE EXCEPTION 'BD01B_DIRECT_SEQUENCE_PRIVILEGE: % %',
      r.login_name, r.sequence_name;
  END LOOP;

  RAISE NOTICE 'BD-01B MQTT least-privilege assertions passed';
END
$bd01$;

ROLLBACK;
