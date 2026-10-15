# Kiro Spec — Design: Roles y Permisos de Food Store
## Unidad 5, Parte A — Base de Datos II

---

## Decisiones de diseño

### D-01 — Justificación de cada rol (una oración)

- **rol_app_lectura**: Habilita `SELECT` sobre `categoria`, `producto`, `pedido` y
  `detalle_pedido` porque la aplicación web necesita mostrar el catálogo, el stock disponible
  y el historial de pedidos del usuario sin modificar nada.

- **rol_app_escritura**: Habilita `INSERT`, `UPDATE` y `DELETE` sobre `pedido` y
  `detalle_pedido`, y `UPDATE` sobre la columna `stock_producto` de `producto`, porque la app
  necesita registrar nuevas órdenes, actualizar su estado y descontar stock al confirmarlas.

- **rol_soporte**: Habilita `SELECT` exclusivamente sobre las columnas no sensibles de
  `usuario` (sin `contrasena_usuario`) y sobre `pedido` y `celular`, porque el equipo de
  soporte necesita identificar al cliente y consultar sus órdenes para resolver incidencias,
  sin exponer su contraseña ni comprometer la seguridad de la cuenta.

- **rol_reportes**: Habilita `SELECT` sobre `categoria`, `producto`, `pedido` y
  `detalle_pedido` porque el área de análisis necesita generar informes de ventas, productos
  más vendidos y facturación por categoría, operaciones que no requieren modificar datos.

- **app_web**: Es el rol de login que usa la aplicación web en producción; hereda
  `rol_app_lectura` y `rol_app_escritura` porque la app necesita operar en modo lectura y
  escritura dentro de los límites estrictamente definidos por esos grupos, sin acceso directo
  a datos administrativos.

- **admin_datos**: Es el rol de login del DBA; hereda todos los grupos de rol para poder
  realizar mantenimiento, migraciones y diagnósticos, pero **no** es superusuario para que
  sus acciones queden dentro del alcance auditable del motor.

---

### D-02 — Permiso a nivel de columna sobre `usuario`

La tabla `usuario` contiene `contrasena_usuario` (hash bcrypt) y `mail_usuario`. Ambos son
datos sensibles. El diseño establece:

- **`rol_soporte`** recibe `SELECT` solo sobre columnas que necesita para identificar al
  cliente en una incidencia:
  `id_usuario`, `nombre_usuario`, `apellido_usuario`, `rol_usuario`,
  `eliminado_usuario`, `created_at_usuario`.

- **`mail_usuario`**: Es necesario para que soporte pueda contactar al cliente. Se incluye.

- **`contrasena_usuario`**: **Nunca** se incluye en ningún `GRANT` de grupo. Solo `admin_datos`
  puede acceder a ella como usuario de login con privilegios de DBA.

---

### D-03 — Estructura de herencia

```
                        ┌─────────────────┐
                        │   app_web        │  (LOGIN, INHERIT)
                        │   CONNECTION 20  │
                        └────────┬────────┘
                    GRANT        │         GRANT
          ┌──────────────────────┤───────────────────────┐
          ▼                      │                        ▼
┌──────────────────┐             │             ┌────────────────────┐
│  rol_app_lectura │             │             │  rol_app_escritura │
│  (NOLOGIN)       │             │             │  (NOLOGIN)         │
└──────────────────┘             │             └────────────────────┘
                                 │
                        ┌────────┴────────┐
                        │  admin_datos    │  (LOGIN, INHERIT)
                        │  CONNECTION 5   │
                        └────────┬────────┘
               GRANT a los 4 grupos de rol
          ┌──────────┬───────────┴──────────┐
          ▼          ▼                       ▼
  rol_app_lectura  rol_app_escritura  rol_soporte  rol_reportes
```

---

### D-04 — Tablas y privilegios (matriz de permisos)

| Tabla            | rol_app_lectura   | rol_app_escritura        | rol_soporte              | rol_reportes    |
|------------------|-------------------|--------------------------|--------------------------|-----------------|
| `categoria`      | SELECT            | —                        | —                        | SELECT          |
| `producto`       | SELECT            | UPDATE (stock_producto)  | —                        | SELECT          |
| `pedido`         | SELECT            | SELECT, INSERT, UPDATE   | SELECT                   | SELECT          |
| `detalle_pedido` | SELECT            | SELECT, INSERT, UPDATE, DELETE | SELECT            | SELECT          |
| `usuario`        | —                 | —                        | SELECT (cols. no sensibles) | —            |
| `celular`        | —                 | —                        | SELECT                   | —               |

---

### D-05 — Artefactos de implementación

| Archivo              | Descripción                                              |
|----------------------|----------------------------------------------------------|
| `sql/roles.sql`      | Script completo: CREATE ROLE, GRANT, REVOKE, ALTER DEFAULT PRIVILEGES |
| `sql/verificacion_permisos.sql` | Consultas a `information_schema` para validar permisos |
| `BITACORA.md`        | Registro de interacciones con OpenCode y validaciones    |
