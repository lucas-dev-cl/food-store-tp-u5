# Kiro Spec — Requirements: Roles y Permisos de Food Store
## Unidad 5, Parte A — Base de Datos II

---

## Contexto del sistema

Food Store es una aplicación de delivery de comida (pizzas, empanadas, bebidas y postres) que
gestiona categorías, productos, usuarios finales, pedidos y detalles de pedido.

Las tablas del schema `public` son:
- `categoria` — catálogo de categorías de productos
- `producto` — productos con precio, stock y disponibilidad
- `usuario` — clientes y administradores del sistema (con contraseña hasheada)
- `celular` — teléfonos asociados a usuarios (relación 1:N)
- `pedido` — órdenes realizadas por usuarios
- `detalle_pedido` — ítems dentro de cada pedido

La tabla `usuario` almacena `contrasena_usuario` (hash bcrypt), `mail_usuario` y `rol_usuario`
(ENUM: `'ADMIN'` o `'USUARIO'`). Estos campos son **datos sensibles** y deben estar protegidos
bajo el principio de mínimo privilegio.

---

## Requisitos funcionales de seguridad

### RF-01 — Separación entre roles de grupo y roles de login
Los roles de grupo (`rol_*`) agrupan privilegios temáticos y **no se conectan directamente** a
la base. Los roles de login (`app_web`, `admin_datos`) son los únicos que abren sesiones y
heredan de los grupos que necesitan. Esto permite cambiar permisos en un solo lugar.

### RF-02 — Mínimo privilegio por tabla y por columna
Cada rol recibe exactamente los privilegios que necesita para su función:
- `rol_app_lectura`: puede leer catálogo (productos, categorías) y estados de pedidos.
- `rol_app_escritura`: puede crear y modificar pedidos y detalles de pedido.
- `rol_soporte`: puede leer datos de usuario **solo en columnas no sensibles** (sin contraseña).
- `rol_reportes`: puede leer tablas del negocio para generar informes agregados.

### RF-03 — Protección de `contrasena_usuario`
Ningún rol de grupo ni de login (excepto `admin_datos`) debe poder leer la columna
`contrasena_usuario` de la tabla `usuario`. El acceso a esa columna se restringe a nivel de
columna (GRANT SELECT por columna específica).

### RF-04 — Revocación de privilegios públicos
El rol `PUBLIC` de PostgreSQL tiene por defecto USAGE en el schema public y CREATE. Ambos
deben revocarse explícitamente para que el acceso sea solo por los roles definidos.

### RF-05 — Herencia automática para tablas futuras
La sentencia `ALTER DEFAULT PRIVILEGES` garantiza que las tablas creadas en el futuro hereden
automáticamente la política de permisos sin intervención manual.

### RF-06 — Límite de conexiones para roles de login
`app_web` tiene un límite de conexiones concurrentes para evitar saturación del servidor.
`admin_datos` tiene un límite más bajo, ya que es de uso exclusivo del DBA.

---

## Roles requeridos

| Rol              | Tipo   | Función                                                            | NOLOGIN |
|------------------|--------|--------------------------------------------------------------------|---------|
| rol_app_lectura  | Grupo  | SELECT sobre catálogo y pedidos para mostrar la app al usuario     | ✓       |
| rol_app_escritura| Grupo  | INSERT/UPDATE/DELETE sobre pedidos y detalles, UPDATE de stock     | ✓       |
| rol_soporte      | Grupo  | SELECT sobre columnas no sensibles de usuario y pedidos            | ✓       |
| rol_reportes     | Grupo  | SELECT sobre tablas del negocio para informes de ventas            | ✓       |
| app_web          | Login  | Usuario de la aplicación web; hereda lectura + escritura           | ✗       |
| admin_datos      | Login  | DBA; hereda todos los grupos para mantenimiento                    | ✗       |
