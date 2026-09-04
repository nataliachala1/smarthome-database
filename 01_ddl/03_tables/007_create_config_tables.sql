-- ============================================================
-- TABLAS - config
-- ============================================================

CREATE TABLE IF NOT EXISTS config.user_preference (
  id_user_preference UUID         NOT NULL DEFAULT gen_random_uuid(),
  id_user            UUID         NOT NULL,
  language           VARCHAR(10)  NOT NULL DEFAULT 'es',
  theme              VARCHAR(10)  NOT NULL DEFAULT 'claro',
  date_format        VARCHAR(20)  NOT NULL DEFAULT 'DD/MM/YYYY',
  time_format        VARCHAR(5)   NOT NULL DEFAULT '24h',
  currency           VARCHAR(10)  NOT NULL DEFAULT 'COP',
  temperature_unit   VARCHAR(5)   NOT NULL DEFAULT 'C',
  timezone           VARCHAR(100) NOT NULL DEFAULT 'America/Bogota',
  created_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_user_preference PRIMARY KEY (id_user_preference),
  CONSTRAINT uq_user_preference_user UNIQUE (id_user),
  CONSTRAINT fk_user_preference_user FOREIGN KEY (id_user) REFERENCES auth."user"(id_user),
  CONSTRAINT ck_user_preference_language CHECK (language IN ('es', 'en', 'fr', 'de')),
  CONSTRAINT ck_user_preference_theme CHECK (theme IN ('claro', 'oscuro', 'automatico')),
  CONSTRAINT ck_user_preference_time_format CHECK (time_format IN ('12h', '24h')),
  CONSTRAINT ck_user_preference_temperature_unit CHECK (temperature_unit IN ('C', 'F'))
);

CREATE TABLE IF NOT EXISTS config.home_recommendation_preference (
  id_home_recommendation_preference UUID        NOT NULL DEFAULT gen_random_uuid(),
  id_home                           UUID        NOT NULL,
  recommendations_enabled           BOOLEAN     NOT NULL DEFAULT TRUE,
  recommendation_frequency          VARCHAR(10) NOT NULL DEFAULT 'semanal',
  created_at                        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_home_recommendation_preference PRIMARY KEY (id_home_recommendation_preference),
  CONSTRAINT uq_home_recommendation_preference_home UNIQUE (id_home),
  CONSTRAINT fk_home_recommendation_preference_home FOREIGN KEY (id_home) REFERENCES homes.home(id_home),
  CONSTRAINT ck_home_recommendation_frequency CHECK (recommendation_frequency IN ('diaria', 'semanal', 'mensual'))
);

CREATE TABLE IF NOT EXISTS config.home_notification_preference (
  id_home_notification_preference UUID        NOT NULL DEFAULT gen_random_uuid(),
  id_home                         UUID        NOT NULL,
  notifications_enabled           BOOLEAN     NOT NULL DEFAULT TRUE,
  high_consumption_notifications  BOOLEAN     NOT NULL DEFAULT TRUE,
  device_notifications            BOOLEAN     NOT NULL DEFAULT TRUE,
  recommendation_notifications    BOOLEAN     NOT NULL DEFAULT TRUE,
  minimum_priority                VARCHAR(10) NOT NULL DEFAULT 'baja',
  created_at                      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_home_notification_preference PRIMARY KEY (id_home_notification_preference),
  CONSTRAINT uq_home_notification_preference_home UNIQUE (id_home),
  CONSTRAINT fk_home_notification_preference_home FOREIGN KEY (id_home) REFERENCES homes.home(id_home),
  CONSTRAINT ck_home_notification_preference_priority CHECK (minimum_priority IN ('baja', 'media', 'alta'))
);
