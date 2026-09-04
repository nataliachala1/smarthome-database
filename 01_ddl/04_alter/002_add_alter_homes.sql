ALTER TABLE homes.home
  ADD CONSTRAINT fk_home_created_by
  FOREIGN KEY (created_by) REFERENCES auth."user"(id_user);

ALTER TABLE homes.zone
  ADD CONSTRAINT fk_zone_home
  FOREIGN KEY (id_home) REFERENCES homes.home(id_home);

ALTER TABLE homes.electricity_tariff
  ADD CONSTRAINT fk_tariff_home
    FOREIGN KEY (id_home) REFERENCES homes.home(id_home),
  ADD CONSTRAINT fk_tariff_created_by
    FOREIGN KEY (created_by) REFERENCES auth."user"(id_user);

ALTER TABLE homes.home_member
  ADD CONSTRAINT fk_home_member_home
    FOREIGN KEY (id_home) REFERENCES homes.home(id_home),
  ADD CONSTRAINT fk_home_member_user
    FOREIGN KEY (id_user) REFERENCES auth."user"(id_user),
  ADD CONSTRAINT fk_home_member_invited_by
    FOREIGN KEY (invited_by) REFERENCES auth."user"(id_user);
