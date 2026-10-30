-- SQL035 / DEV / flespi: ledger para idempotencia transaccional.
-- Se crea una tabla NORMAL porque consumption.consumption está particionada
-- por read_at; su PK (id_consumption, read_at) no protege la identidad MQTT.
-- El ledger NO deduplica por igualdad de valores eléctricos ni por hora
-- de recepción: el backend debe suministrar una identidad de evento estable.

CREATE TABLE consumption.mqtt_ingest_dedup (
    id_device          UUID          NOT NULL,
    id_home            UUID          NOT NULL,
    event_key          VARCHAR(64)   NOT NULL,
    source_topic       VARCHAR(256)  NOT NULL,
    device_event_ts    NUMERIC(18,6) NOT NULL,
    first_received_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT pk_mqtt_ingest_dedup PRIMARY KEY (id_device, event_key),
    CONSTRAINT fk_mqtt_ingest_dedup_device_home
        FOREIGN KEY (id_device, id_home)
        REFERENCES devices.device (id_device, id_home),
    CONSTRAINT ck_mqtt_ingest_dedup_event_key
        CHECK (event_key ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_mqtt_ingest_dedup_source_topic
        CHECK (source_topic ~ '^smarthome/dev/v1/devices/[A-Za-z0-9_.:-]+/(events/rpc|status/switch:[0-9]+)$'),
    CONSTRAINT ck_mqtt_ingest_dedup_device_ts
        CHECK (device_event_ts > 0)
);

CREATE INDEX idx_mqtt_ingest_dedup_received_at
    ON consumption.mqtt_ingest_dedup (first_received_at);

-- Segregación: solo la identidad de ingesta registra o lee su propio ledger.
-- RETURNING y ON CONFLICT (id_device, event_key) requieren SELECT sobre
-- columnas de identificación además de INSERT sobre las de escritura.
REVOKE ALL ON TABLE consumption.mqtt_ingest_dedup FROM PUBLIC;
GRANT INSERT (id_device, id_home, event_key, source_topic, device_event_ts)
    ON consumption.mqtt_ingest_dedup TO smarthome_ingest;
GRANT SELECT (id_device, id_home, event_key)
    ON consumption.mqtt_ingest_dedup TO smarthome_ingest;

ALTER TABLE consumption.mqtt_ingest_dedup ENABLE ROW LEVEL SECURITY;

CREATE POLICY mqtt_ingest_dedup_insert_policy
    ON consumption.mqtt_ingest_dedup
    FOR INSERT TO smarthome_ingest
    WITH CHECK (
        devices.fn_is_ingestable_device(id_device)
        AND devices.fn_device_belongs_to_home(id_device, id_home)
    );

CREATE POLICY mqtt_ingest_dedup_select_policy
    ON consumption.mqtt_ingest_dedup
    FOR SELECT TO smarthome_ingest
    USING (
        devices.fn_is_ingestable_device(id_device)
        AND devices.fn_device_belongs_to_home(id_device, id_home)
    );

COMMENT ON TABLE consumption.mqtt_ingest_dedup IS
    'SQL035: registra eventos Shelly con identidad estable para deduplicar inserciones de consumo en la MISMA transacción; no es historial de energía.';
COMMENT ON COLUMN consumption.mqtt_ingest_dedup.event_key IS
    'SHA-256 hexadecimal de identidad lógica estable versionada; el backend debe rechazar claves basadas solo en recepción o JSON de estado.';
COMMENT ON COLUMN consumption.mqtt_ingest_dedup.device_event_ts IS
    'Timestamp de origen Shelly, usado como parte de la identidad; no garantiza unicidad por sí mismo.';
