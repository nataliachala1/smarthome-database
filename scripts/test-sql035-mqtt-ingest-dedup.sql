-- Solo ejecutar DESPUÉS de instalar SQL035 en una BD de prueba.
-- Validación estructural, sin inserciones ni modificaciones de datos.
DO $check$
DECLARE
    enabled BOOLEAN;
BEGIN
    IF to_regclass('consumption.mqtt_ingest_dedup') IS NULL THEN
        RAISE EXCEPTION 'SQL035_TABLE_MISSING';
    END IF;

    SELECT c.relrowsecurity INTO enabled
    FROM pg_class c WHERE c.oid = 'consumption.mqtt_ingest_dedup'::regclass;
    IF enabled IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'SQL035_RLS_DISABLED';
    END IF;

    IF NOT EXISTS (
       SELECT 1 FROM pg_constraint
       WHERE conrelid = 'consumption.mqtt_ingest_dedup'::regclass
         AND contype = 'p'
         AND conname = 'pk_mqtt_ingest_dedup'
    ) THEN RAISE EXCEPTION 'SQL035_PK_MISSING'; END IF;

    IF NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'consumption'
         AND tablename = 'mqtt_ingest_dedup'
         AND policyname = 'mqtt_ingest_dedup_insert_policy'
    ) THEN RAISE EXCEPTION 'SQL035_INSERT_POLICY_MISSING'; END IF;

    IF NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'consumption'
         AND tablename = 'mqtt_ingest_dedup'
         AND policyname = 'mqtt_ingest_dedup_select_policy'
    ) THEN RAISE EXCEPTION 'SQL035_SELECT_POLICY_MISSING'; END IF;

    IF NOT has_column_privilege('smarthome_ingest',
       'consumption.mqtt_ingest_dedup', 'event_key', 'INSERT') THEN
        RAISE EXCEPTION 'SQL035_INGEST_INSERT_NOT_ALLOWED';
    END IF;

    IF NOT has_column_privilege('smarthome_ingest',
       'consumption.mqtt_ingest_dedup', 'event_key', 'SELECT') THEN
        RAISE EXCEPTION 'SQL035_INGEST_SELECT_NOT_ALLOWED';
    END IF;

    IF has_table_privilege('smarthome_runtime_app',
       'consumption.mqtt_ingest_dedup', 'INSERT') THEN
        RAISE EXCEPTION 'SQL035_APP_SHOULD_NOT_INSERT';
    END IF;

    RAISE NOTICE 'SQL035 structural checks passed; run an actual RLS, concurrency, and rollback integration test separately.';
END $check$;
