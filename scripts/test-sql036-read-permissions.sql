-- Structural checks only: no test fixtures and no data changes.
DO $$
BEGIN
  IF to_regclass('consumption.mqtt_ingest_dedup') IS NULL THEN
    RAISE EXCEPTION 'SQL036_PRECONDITION_MISSING_SQL035';
  END IF;
  IF NOT has_column_privilege('smarthome_ingest', 'consumption.mqtt_ingest_dedup', 'device_event_ts', 'SELECT') THEN
    RAISE EXCEPTION 'SQL036_MISSING_TIMESTAMP_SELECT';
  END IF;
  IF has_column_privilege('smarthome_ingest', 'consumption.mqtt_ingest_dedup', 'source_topic', 'SELECT')
     OR has_column_privilege('smarthome_ingest', 'consumption.mqtt_ingest_dedup', 'first_received_at', 'SELECT') THEN
    RAISE EXCEPTION 'SQL036_EXCESSIVE_SELECT_PRIVILEGES';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'consumption'
      AND tablename = 'mqtt_ingest_dedup'
      AND indexname = 'idx_mqtt_ingest_dedup_device_event_ts'
      AND indexdef LIKE '%(id_device, device_event_ts DESC)%'
  ) THEN
    RAISE EXCEPTION 'SQL036_MISSING_DEVICE_TIMESTAMP_INDEX';
  END IF;
  RAISE NOTICE 'SQL036_PASS: minimal timestamp permission and index verified';
END;
$$;
