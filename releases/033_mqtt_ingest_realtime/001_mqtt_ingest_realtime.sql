-- SEGURIDAD: negar lecturas directas de hogares a la ingesta MQTT.
-- Unicamente se consulta destinatarios con la funcion SECURITY DEFINER.
REVOKE SELECT ON TABLE homes.home, homes.home_member FROM smarthome_ingest;
-- SQL033: permisos mínimos para ingesta MQTT y eventos realtime.
-- Requiere revisión y validación Liquibase antes de su aplicación.

-- El subscriber filtra la lectura anterior por id_home.
GRANT SELECT (id_home)
ON consumption.consumption
TO smarthome_ingest;

-- Devuelve destinatarios únicamente para un dispositivo MQTT activo
-- que pertenezca al hogar indicado.
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