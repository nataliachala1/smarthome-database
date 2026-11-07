-- For safety, never automatically revert an authenticated operation
-- or the audited transition events. Run an explicit DBA review.
DO $$
BEGIN
  RAISE EXCEPTION USING ERRCODE='55000',
    MESSAGE='MQTT_029_ROLLBACK_MANUAL_REVIEW_REQUIRED';
END;
$$;
