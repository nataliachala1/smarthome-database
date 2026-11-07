-- ============================================================
-- TECHNICAL FUNCTIONS - updated_at
-- File: 01_ddl/07_functions/001_update_functions.sql
--
-- Responsibility:
--   Maintain updated_at through technical triggers.
--
-- Contains no business logic.
-- Does not use SECURITY DEFINER.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_set_updated_at()
IS 'Trigger function tecnica que actualiza NEW.updated_at antes de persistir un UPDATE.';
