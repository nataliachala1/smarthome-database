# HU16 — Permisos de hogar y excepciones por dispositivo

La release `018_household_permissions` añade almacenamiento de permisos base por membresía y excepciones anulables por dispositivo. Las membresías anteriores reciben valores base equivalentes a su rol: `MEMBER` puede consultar y controlar; `GUEST` puede consultar y no puede controlar. Ambos pueden consultar el resumen agregado del hogar. `OWNER` conserva la administración completa.

Las excepciones por dispositivo controlan consulta descriptiva, consumo detallado y control. `NULL` hereda el permiso del hogar. Para `GUEST`, el acceso al consumo detallado sigue denegado aunque una excepción tenga `can_view_consumption = TRUE`; el endpoint agregado solo devuelve energía total y período.

Las funciones SQL de lectura y escritura verifican `OWNER`. RLS filtra los dispositivos y filas energéticas por permiso efectivo. La lectura de un dispositivo para publicar un comando de control usa `devices.fn_device_control_target`, autorizada solo por permiso de control; el endpoint no devuelve estado previo ni conectividad.

Las rutas REST de gestión y DTO están documentados en backend `docs/ROLES_Y_PERMISOS.md`. Esta release no se aplica a ninguna base activa; debe desplegarse mediante la secuencia aprobada de Liquibase en `16-dev`.
