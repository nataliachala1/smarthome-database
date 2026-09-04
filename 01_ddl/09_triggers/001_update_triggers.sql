-- Triggers técnicos de updated_at. No contienen lógica de negocio.

DROP TRIGGER IF EXISTS trg_user_updated_at ON auth."user";
CREATE TRIGGER trg_user_updated_at BEFORE UPDATE ON auth."user"
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_home_updated_at ON homes.home;
CREATE TRIGGER trg_home_updated_at BEFORE UPDATE ON homes.home
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_zone_updated_at ON homes.zone;
CREATE TRIGGER trg_zone_updated_at BEFORE UPDATE ON homes.zone
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_home_member_updated_at ON homes.home_member;
CREATE TRIGGER trg_home_member_updated_at BEFORE UPDATE ON homes.home_member
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_device_type_updated_at ON devices.device_type;
CREATE TRIGGER trg_device_type_updated_at BEFORE UPDATE ON devices.device_type
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_device_updated_at ON devices.device;
CREATE TRIGGER trg_device_updated_at BEFORE UPDATE ON devices.device
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_smart_device_updated_at ON devices.smart_device;
CREATE TRIGGER trg_smart_device_updated_at BEFORE UPDATE ON devices.smart_device
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_device_schedule_updated_at ON devices.device_schedule;
CREATE TRIGGER trg_device_schedule_updated_at BEFORE UPDATE ON devices.device_schedule
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_consumption_metric_updated_at ON consumption.consumption_metric;
CREATE TRIGGER trg_consumption_metric_updated_at BEFORE UPDATE ON consumption.consumption_metric
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_recommendation_updated_at ON consumption.recommendation;
CREATE TRIGGER trg_recommendation_updated_at BEFORE UPDATE ON consumption.recommendation
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_notification_updated_at ON notifications.notification;
CREATE TRIGGER trg_notification_updated_at BEFORE UPDATE ON notifications.notification
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_alert_rule_updated_at ON notifications.alert_rule;
CREATE TRIGGER trg_alert_rule_updated_at BEFORE UPDATE ON notifications.alert_rule
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_user_preference_updated_at ON config.user_preference;
CREATE TRIGGER trg_user_preference_updated_at BEFORE UPDATE ON config.user_preference
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_home_recommendation_preference_updated_at ON config.home_recommendation_preference;
CREATE TRIGGER trg_home_recommendation_preference_updated_at BEFORE UPDATE ON config.home_recommendation_preference
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_home_notification_preference_updated_at ON config.home_notification_preference;
CREATE TRIGGER trg_home_notification_preference_updated_at BEFORE UPDATE ON config.home_notification_preference
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_backup_updated_at ON sync.backup;
CREATE TRIGGER trg_backup_updated_at BEFORE UPDATE ON sync.backup
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();
