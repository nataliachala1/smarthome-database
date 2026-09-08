ALTER TABLE homes.home_member
  DROP CONSTRAINT IF EXISTS fk_home_member_invited_by,
  DROP CONSTRAINT IF EXISTS fk_home_member_user,
  DROP CONSTRAINT IF EXISTS fk_home_member_home;

ALTER TABLE homes.home DROP CONSTRAINT IF EXISTS fk_home_created_by;
