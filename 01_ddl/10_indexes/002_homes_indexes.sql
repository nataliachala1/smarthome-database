-- Índices de homes y reglas de unicidad contextual.
CREATE INDEX IF NOT EXISTS idx_home_created_by_status
  ON homes.home(created_by, status);

CREATE INDEX IF NOT EXISTS idx_zone_home_active
  ON homes.zone(id_home)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_home_member_user_status
  ON homes.home_member(id_user, status);

CREATE INDEX IF NOT EXISTS idx_home_member_home_status
  ON homes.home_member(id_home, status);

CREATE UNIQUE INDEX IF NOT EXISTS uq_home_member_current_membership
  ON homes.home_member(id_home, id_user)
  WHERE status IN ('PENDING', 'ACTIVE');

CREATE UNIQUE INDEX IF NOT EXISTS uq_home_member_active_owner
  ON homes.home_member(id_home)
  WHERE role = 'OWNER' AND status = 'ACTIVE';

CREATE INDEX IF NOT EXISTS idx_electricity_tariff_home_valid_from
  ON homes.electricity_tariff(id_home, valid_from DESC);
