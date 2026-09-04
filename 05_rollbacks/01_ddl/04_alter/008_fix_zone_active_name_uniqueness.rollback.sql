DROP INDEX IF EXISTS homes.uq_zone_name;

ALTER TABLE homes.zone
ADD CONSTRAINT uq_zone_name
UNIQUE (id_home, name);