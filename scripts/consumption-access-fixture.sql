-- ONLY for the fresh disposable database created by test-consumption-access.ps1.
DO $$ BEGIN
  IF current_database() <> 'smarthome_consumption_test' THEN
    RAISE EXCEPTION 'Consumption fixture requires its disposable database';
  END IF;
END $$;

CREATE ROLE consumption_app_test LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE PASSWORD :'app_password';
GRANT smarthome_app TO consumption_app_test;

INSERT INTO auth."user"(id_user, name, email, password_hash, status, email_verified, deactivated_at)
SELECT ('10000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
       'Synthetic ' || n, 'test' || n || '@example.test', 'fixture-only',
       CASE WHEN n=8 THEN 'DEACTIVATED' ELSE 'ACTIVE' END, true,
       CASE WHEN n=8 THEN now() ELSE NULL END
FROM generate_series(1,10) n;

INSERT INTO homes.home(id_home, created_by, name, status, deleted_at) VALUES
('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000009','Synthetic A','ACTIVE',NULL),
('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000004','Synthetic B','ACTIVE',NULL),
('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001','Synthetic inactive','DEACTIVATED',now());

INSERT INTO homes.home_member(id_home, id_user, role, status, accepted_at, ended_at)
SELECT '20000000-0000-4000-8000-000000000001'::uuid,
       ('10000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
       CASE WHEN n=1 THEN 'OWNER' WHEN n=3 THEN 'GUEST' ELSE 'MEMBER' END,
       CASE WHEN n=5 THEN 'PENDING' WHEN n=6 THEN 'REVOKED' WHEN n=7 THEN 'LEFT' ELSE 'ACTIVE' END,
       CASE WHEN n=5 THEN NULL ELSE now() END,
       CASE WHEN n IN (6,7) THEN now() ELSE NULL END
FROM generate_series(1,10) n WHERE n NOT IN (4,9);
INSERT INTO homes.home_member(id_home,id_user,role,status,accepted_at) VALUES
('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000004','OWNER','ACTIVE',now()),
('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001','OWNER','ACTIVE',now()),
('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000002','MEMBER','ACTIVE',now());

INSERT INTO devices.device(id_device,id_home,name,manufacturer_device_id,status,deleted_at) VALUES
('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','Active synthetic','synthetic-1','ACTIVE',NULL),
('40000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','Inactive synthetic','synthetic-2','DEACTIVATED',NULL),
('40000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000001','Removed synthetic','synthetic-3','DEACTIVATED',now()),
('40000000-0000-4000-8000-000000000004','20000000-0000-4000-8000-000000000002','Foreign synthetic','synthetic-4','ACTIVE',NULL),
('40000000-0000-4000-8000-000000000005','20000000-0000-4000-8000-000000000001','Empty synthetic','synthetic-5','ACTIVE',NULL),
('40000000-0000-4000-8000-000000000006','20000000-0000-4000-8000-000000000003','Inactive home synthetic','synthetic-6','DEACTIVATED',NULL);

INSERT INTO consumption.consumption(id_home,id_device,power_w,energy_delta_kwh,energy_total_kwh,read_at) VALUES
('20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001',100,0.1,10.1,'2026-10-10T12:00:00Z'),
('20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001',200,0.2,10.3,'2026-10-11T12:00:00Z'),
('20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000002',300,0.4,15,'2026-10-11T13:00:00Z'),
('20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000003',400,0.6,20,'2026-10-12T12:00:00Z'),
('20000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000004',900,9,90,'2026-10-10T12:00:00Z');

INSERT INTO consumption.consumption_metric(id_home,id_device,period,start_at,end_at,kwh_total) VALUES
('20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','dia','2026-10-10','2026-10-11',0.1),
('20000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000004','dia','2026-10-10','2026-10-11',9);

INSERT INTO auth.refresh_token(id_user,token_hash,family_id,session_version,expires_at)
SELECT id_user, 'synthetic-family-' || id_user::text,
       ('30000000-0000-4000-8000-' || right(id_user::text,12))::uuid, session_version, now() + interval '1 day'
FROM auth."user" WHERE email LIKE 'test%@example.test';
