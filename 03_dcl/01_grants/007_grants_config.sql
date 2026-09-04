GRANT USAGE ON SCHEMA config
TO smarthome_admin, smarthome_app, smarthome_ingest, smarthome_worker;

GRANT SELECT, INSERT ON TABLE config.user_preference TO smarthome_admin, smarthome_app;
GRANT UPDATE (language, theme, date_format, time_format, currency, temperature_unit, timezone)
ON TABLE config.user_preference TO smarthome_app;
GRANT UPDATE ON TABLE config.user_preference TO smarthome_admin;

GRANT SELECT, INSERT ON TABLE config.home_recommendation_preference TO smarthome_admin, smarthome_app;
GRANT UPDATE (recommendations_enabled, recommendation_frequency)
ON TABLE config.home_recommendation_preference TO smarthome_app;
GRANT UPDATE ON TABLE config.home_recommendation_preference TO smarthome_admin;
GRANT SELECT ON TABLE config.home_recommendation_preference TO smarthome_worker;

GRANT SELECT, INSERT ON TABLE config.home_notification_preference TO smarthome_admin, smarthome_app;
GRANT UPDATE (notifications_enabled, high_consumption_notifications, device_notifications, recommendation_notifications, minimum_priority)
ON TABLE config.home_notification_preference TO smarthome_app;
GRANT UPDATE ON TABLE config.home_notification_preference TO smarthome_admin;
GRANT SELECT ON TABLE config.home_notification_preference TO smarthome_ingest, smarthome_worker;
