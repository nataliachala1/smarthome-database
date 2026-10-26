-- Por seguridad, nunca revertir automaticamente una operacion autenticada
-- ni los eventos de transicion auditados. Ejecutar revision DBA explicita.
DO $$
BEGIN
  RAISE EXCEPTION USING ERRCODE='55000',
    MESSAGE='MQTT_029_ROLLBACK_MANUAL_REVIEW_REQUIRED';
END;
$$;
