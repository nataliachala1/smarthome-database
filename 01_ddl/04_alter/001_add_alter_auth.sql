ALTER TABLE auth."user"
  ADD CONSTRAINT fk_user_role
  FOREIGN KEY (id_role) REFERENCES auth.role(id_role);

ALTER TABLE auth.recovery_token
  ADD CONSTRAINT fk_recovery_token_user
  FOREIGN KEY (id_user) REFERENCES auth."user"(id_user);
