-- pgcrypto: Generates UUIDs for all primary keys.
-- Required by: all tables with UUID primary keys.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
