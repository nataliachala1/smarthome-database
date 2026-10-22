# Backup y restauración

El VPS reporta un backup pequeño frente al volumen PostgreSQL conocido. No se ha demostrado que ese archivo contenga una copia completa y restaurable; no debe usarse como punto de recuperación hasta probarlo.

## Crear un backup verificado

Durante la auditoría, identifica la instancia, su base y su usuario de mantenimiento antes de ejecutar `pg_dump`. Guarda el dump fuera del volumen de PostgreSQL y, preferiblemente, fuera del VPS. Conserva permisos restrictivos y registra fecha, versión del servidor, tamaño y checksum.

Ejemplo para ejecutar con los valores identificados, sin guardar contraseñas en el historial del shell:

```sh
pg_dump --format=custom --no-owner --file=smarthome-YYYYMMDDTHHMMSSZ.dump "$DATABASE_URL"
pg_restore --list smarthome-YYYYMMDDTHHMMSSZ.dump >/dev/null
sha256sum smarthome-YYYYMMDDTHHMMSSZ.dump
```

## Prueba de restauración

Restaura el dump en una base PostgreSQL aislada que no sea la producción. Usa `pg_restore --exit-on-error`, valida tablas y conteos de control y conserva el resultado de la prueba junto al registro operativo. No uses `--clean`, no apuntes la prueba a la base de producción y no elimines el dump original.

## Recuperación

Antes de recuperar, detén escrituras de la aplicación y conserva el volumen original. Restaura en una base aparte, valida los datos y coordina cualquier cambio de endpoint. La restauración no se automatiza con el despliegue.
