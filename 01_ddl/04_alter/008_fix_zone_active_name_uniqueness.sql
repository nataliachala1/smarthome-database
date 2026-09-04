ALTER TABLE homes.zone
DROP CONSTRAINT uq_zone_name;

CREATE UNIQUE INDEX uq_zone_name
ON homes.zone (id_home, name)
WHERE deleted_at IS NULL;