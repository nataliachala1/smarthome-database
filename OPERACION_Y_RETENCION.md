# Operación y retención

## Telemetría cruda

`devices.device_telemetry_raw` es diagnóstica y no debe crecer indefinidamente. El baseline no ejecuta purgas mediante Liquibase. El worker/operación técnica debe aplicar una retención configurable; valor inicial recomendado para desarrollo: 30 días.

## Auditoría

`identity_audit.audit_log` es append-only para los roles de aplicación. Debe conservarse al menos 12 meses antes de cualquier archivado/purga autorizado por infraestructura.

## Particiones de consumo

El baseline conserva una partición `DEFAULT` como red de seguridad. Antes de habilitar la ingesta, y luego de forma periódica, `smarthome_worker` debe ejecutar:

```sql
SELECT consumption.fn_ensure_consumption_partitions(2);
```

## Backups

`sync.backup` solo registra metadata. `pg_dump`, `pg_restore`, snapshots u otros mecanismos de infraestructura realizan el backup/restauración reales.

La llamada debe realizarse antes de que la partición `DEFAULT` acumule filas del mes que se desea materializar; en producción se recomienda ejecutar el mantenimiento al arrancar el worker y al menos una vez al mes.
