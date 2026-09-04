REVOKE SELECT ON TABLE config.home_notification_preference FROM smarthome_ingest, smarthome_worker;
REVOKE UPDATE ON TABLE config.home_notification_preference FROM smarthome_admin;
REVOKE UPDATE (notifications_enabled, high_consumption_notifications, device_notifications, recommendation_notifications, minimum_priority) ON TABLE config.home_notification_preference FROM smarthome_app;
REVOKE SELECT, INSERT ON TABLE config.home_notification_preference FROM smarthome_admin, smarthome_app;

REVOKE SELECT ON TABLE config.home_recommendation_preference FROM smarthome_worker;
REVOKE UPDATE ON TABLE config.home_recommendation_preference FROM smarthome_admin;
REVOKE UPDATE (recommendations_enabled, recommendation_frequency) ON TABLE config.home_recommendation_preference FROM smarthome_app;
REVOKE SELECT, INSERT ON TABLE config.home_recommendation_preference FROM smarthome_admin, smarthome_app;

REVOKE UPDATE ON TABLE config.user_preference FROM smarthome_admin;
REVOKE UPDATE (language, theme, date_format, time_format, currency, temperature_unit, timezone) ON TABLE config.user_preference FROM smarthome_app;
REVOKE SELECT, INSERT ON TABLE config.user_preference FROM smarthome_admin, smarthome_app;
REVOKE USAGE ON SCHEMA config FROM smarthome_admin, smarthome_app, smarthome_ingest, smarthome_worker;
