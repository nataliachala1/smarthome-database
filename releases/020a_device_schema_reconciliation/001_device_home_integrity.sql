-- Reconciliacion de integridad dispositivo-hogar.
-- No modifica ni elimina dispositivos existentes.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'devices.device'::regclass
          AND conname = 'fk_device_home'
    ) THEN
        ALTER TABLE devices.device
            ADD CONSTRAINT fk_device_home
            FOREIGN KEY (id_home)
            REFERENCES homes.home(id_home);
    END IF;
END;
$$;
