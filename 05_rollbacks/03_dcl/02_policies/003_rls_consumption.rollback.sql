-- ============================================================
-- ROLLBACK — RLS consumption
-- ============================================================

-- ============================================================
-- consumption.consumption_metric
-- ============================================================

DROP POLICY IF EXISTS
consumption_metric_worker_update_policy
ON consumption.consumption_metric;

DROP POLICY IF EXISTS
consumption_metric_worker_insert_policy
ON consumption.consumption_metric;

DROP POLICY IF EXISTS
consumption_metric_worker_select_policy
ON consumption.consumption_metric;

DROP POLICY IF EXISTS
consumption_metric_app_select_policy
ON consumption.consumption_metric;


ALTER TABLE consumption.consumption_metric
DISABLE ROW LEVEL SECURITY;


-- ============================================================
-- consumption.consumption
-- ============================================================

DROP POLICY IF EXISTS
consumption_worker_select_policy
ON consumption.consumption;

DROP POLICY IF EXISTS
consumption_ingest_insert_policy
ON consumption.consumption;

DROP POLICY IF EXISTS
consumption_ingest_select_policy
ON consumption.consumption;

DROP POLICY IF EXISTS
consumption_app_select_policy
ON consumption.consumption;


ALTER TABLE consumption.consumption
DISABLE ROW LEVEL SECURITY;


-- ============================================================
-- Helper
-- ============================================================

