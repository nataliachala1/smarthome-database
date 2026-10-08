-- ============================================================
-- IoT ingestion: allow existing alert lookup
-- ============================================================

GRANT SELECT
ON TABLE notifications.alert
TO smarthome_ingest;


CREATE POLICY alert_ingest_select_policy
ON notifications.alert
FOR SELECT
TO smarthome_ingest
USING (
    devices.fn_is_ingestable_device(id_device)

    AND devices.fn_device_belongs_to_home(
        id_device,
        id_home
    )
);