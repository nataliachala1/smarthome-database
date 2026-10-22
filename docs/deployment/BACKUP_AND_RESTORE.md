# Backup y restauración

El servicio `backup` hace un `pg_dump` diario en formato custom después de que PostgreSQL esté saludable. Conserva por defecto 30 días en el volumen Docker `postgres_backups`; configura `BACKUP_RETENTION_DAYS` en Dokploy. El backup está en el mismo VPS y no protege contra pérdida del VPS: copia los dumps a un almacenamiento externo y restringe quién puede leerlos.

## Comprobar un dump

```sh
docker compose -f docker-compose.production.yml exec backup sh -ec 'ls -lh /backups && pg_restore --list "$(ls -1t /backups/smarthome-*.dump | head -n 1)" >/dev/null'
```

## Prueba de restauración

Restaura periódicamente en un PostgreSQL aislado que no sea el servicio de producción. Crea una base de prueba vacía, restaura ahí el dump con `pg_restore --exit-on-error`, y verifica tablas clave y conteos de control. No uses `--clean`, no apuntes esta prueba a la base de producción y no elimines el dump usado.

Ejemplo con un servicio PostgreSQL aislado llamado `restore-postgres` en una red temporal:

```sh
pg_restore --verbose --exit-on-error --no-owner --dbname=smarthome_restore_test /backups/smarthome-YYYYMMDDTHHMMSSZ.dump
```

El usuario operador debe crear la base aislada antes. Mantén el resultado de la prueba y fecha junto al registro operativo.

## Recuperación

Para recuperar, detén escrituras de la aplicación, conserva el volumen original, restaura el dump en una base aparte y verifica los datos antes de cambiar el endpoint. Coordina el procedimiento con el cambio de `DATABASE_URL`/`DATABASE_IOT_URL`. Una restauración de datos no se automatiza con el despliegue.
