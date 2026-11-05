-- ============================================================
-- FUNCIONES TECNICAS - particionado de consumo
-- Archivo: 01_ddl/07_functions/005_consumption_partition_functions.sql
--
-- La tabla padre consumption.consumption debe existir como:
--   PARTITION BY RANGE (read_at)
--
-- Esta funcion crea la particion del mes actual y una cantidad
-- controlada de meses futuros.
-- ============================================================

CREATE OR REPLACE FUNCTION consumption.fn_ensure_consumption_partitions(
    p_months_ahead INT DEFAULT 2
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, consumption
SET TimeZone = 'UTC'
AS $$
DECLARE
    v_index          INT;
    v_from           TIMESTAMPTZ;
    v_to             TIMESTAMPTZ;
    v_partition_name TEXT;
BEGIN
    IF p_months_ahead IS NULL OR p_months_ahead < 0 OR p_months_ahead > 24 THEN
        RAISE EXCEPTION
            'p_months_ahead debe estar entre 0 y 24; recibido: %',
            p_months_ahead
            USING ERRCODE = '22023';
    END IF;

    FOR v_index IN 0..p_months_ahead LOOP
        v_from := pg_catalog.date_trunc('month', CURRENT_TIMESTAMP)
                  + pg_catalog.make_interval(months => v_index);
        v_to   := v_from + INTERVAL '1 month';

        v_partition_name := 'consumption_' || pg_catalog.to_char(v_from, 'YYYY_MM');

        EXECUTE pg_catalog.format(
            'CREATE TABLE IF NOT EXISTS consumption.%I '
            'PARTITION OF consumption.consumption '
            'FOR VALUES FROM (%L) TO (%L)',
            v_partition_name,
            v_from,
            v_to
        );
    END LOOP;
END;
$$;

REVOKE ALL
ON FUNCTION consumption.fn_ensure_consumption_partitions(INT)
FROM PUBLIC;

COMMENT ON FUNCTION consumption.fn_ensure_consumption_partitions(INT)
IS 'Crea la particion mensual actual y hasta 24 meses futuros para consumption.consumption.';

