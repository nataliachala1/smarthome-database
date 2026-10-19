# Roles y permisos del hogar

`OWNER`, `MEMBER` y `GUEST` son roles de hogar. El rol determina las responsabilidades y permisos iniciales; los permisos concedidos determinan el acceso efectivo de `MEMBER` y `GUEST`. Administrar el hogar, consultar información y controlar dispositivos son capacidades separadas.

| Rol | Administración | Consulta | Control |
| --- | --- | --- | --- |
| `OWNER` | Administra el hogar y sus miembros; invita usuarios y administra dispositivos Shelly. | Consulta los dispositivos y el consumo del hogar. | Puede controlar los dispositivos del hogar. |
| `MEMBER` | No administra la propiedad, propietarios, miembros ni invitaciones. | Permiso base: dispositivos y consumo; puede limitarse por hogar o dispositivo. | Permiso base concedido; puede limitarse o revocarse. |
| `GUEST` | No administra el hogar, configuración, miembros ni invitaciones. | Permiso base para dispositivos. Consumo exclusivamente agregado al hogar y al período consultado. | Sin permiso base; `OWNER` puede conceder control por dispositivo. |

El permiso de consulta no concede control y el control no concede lectura. Las excepciones por dispositivo reemplazan la base del hogar para consultar información del dispositivo, consultar su consumo detallado o controlarlo. Los valores heredados usan la base del hogar. Para `GUEST`, una excepción jamás habilita lecturas o históricos de consumo por dispositivo.

Las bases iniciales se crean automáticamente al insertar una membresía `MEMBER` o `GUEST`. Un cambio de rol reinicia los valores base del rol y elimina excepciones anteriores. `OWNER` gestiona permisos con las funciones SQL protegidas `homes.fn_get_member_permissions`, `homes.fn_set_member_permissions`, `homes.fn_get_device_permissions` y `homes.fn_set_device_permissions`; las tablas internas no conceden DML directo a `smarthome_app`.

La base filtra dispositivos, consumo e historial con RLS y funciones de autorización. Las operaciones de control usan una función `SECURITY DEFINER` que entrega únicamente la fila necesaria si el usuario cuenta con permiso de control, sin ampliar el `SELECT` general.
