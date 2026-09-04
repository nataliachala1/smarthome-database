-- UNIQUE(id_user) y UNIQUE(id_home) ya crean índices adecuados.
-- Este índice ayuda al worker a localizar hogares con recomendaciones habilitadas.
CREATE INDEX IF NOT EXISTS idx_home_recommendation_enabled_frequency
  ON config.home_recommendation_preference(recommendation_frequency)
  WHERE recommendations_enabled = TRUE;
