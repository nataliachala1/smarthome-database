-- SECURITY: deny direct reads of homes to MQTT ingest.
-- Recipients are queried only through the SECURITY DEFINER function.
REVOKE SELECT ON TABLE homes.home, homes.home_member FROM smarthome_ingest;
-- SQL033: minimum permissions for MQTT ingest and realtime events.
-- Requires review and Liquibase validation before being applied.

-- The subscriber filters the previous read by id_home.
GRANT SELECT (id_home)
ON consumption.consumption
TO smarthome_ingest;

-- Returns recipients only for an active MQTT device
-- that belongs to the given home.
CREATE FUNCTION homes.fn_mqtt_realtime_recipients(
    p_device_id UUID,
    p_home_id UUID
)
RETURNS TABLE(id_user UUID)
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT DISTINCT recipients.user_id
    FROM (
        SELECT h.created_by AS user_id
        FROM homes.home h
        WHERE h.id_home = p_home_id
          AND h.status = 'ACTIVE'
          AND h.deleted_at IS NULL

        UNION

        SELECT hm.id_user AS user_id
        FROM homes.home_member hm
        JOIN homes.home h
          ON h.id_home = hm.id_home
        WHERE hm.id_home = p_home_id
          AND hm.status = 'ACTIVE'
          AND h.status = 'ACTIVE'
          AND h.deleted_at IS NULL
    ) recipients
    WHERE recipients.user_id IS NOT NULL
      AND EXISTS (
          SELECT 1
          FROM devices.device d
          WHERE d.id_device = p_device_id
            AND d.id_home = p_home_id
            AND d.status = 'ACTIVE'
            AND d.deleted_at IS NULL
            AND d.messaging_protocol = 'MQTT'
      );
$$;

REVOKE ALL ON FUNCTION
homes.fn_mqtt_realtime_recipients(UUID, UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
homes.fn_mqtt_realtime_recipients(UUID, UUID)
TO smarthome_ingest;