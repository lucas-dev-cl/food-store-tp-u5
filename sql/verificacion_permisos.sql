-- =============================================================================
-- Food Store — Verificación de Roles y Permisos
-- Unidad 5, Parte A — Evidencia de mínimo privilegio
-- Ejecutar después de roles.sql para confirmar que los permisos son correctos.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Atributos de todos los roles del sistema
--    Equivalente a \du pero en SQL puro (útil para adjuntar en el informe).
-- -----------------------------------------------------------------------------

SELECT
    rolname           AS rol,
    rolcanlogin       AS puede_login,
    rolinherit        AS hereda,
    rolcreaterole     AS puede_crear_roles,
    rolcreatedb       AS puede_crear_db,
    rolsuper          AS es_superusuario,
    rolconnlimit      AS limite_conexiones
FROM pg_roles
WHERE rolname IN (
    'rol_app_lectura', 'rol_app_escritura',
    'rol_soporte', 'rol_reportes',
    'app_web', 'admin_datos'
)
ORDER BY rolcanlogin, rolname;

-- Resultado esperado:
--   rol_app_lectura   → puede_login=false, hereda=false, es_superusuario=false
--   rol_app_escritura → puede_login=false, hereda=false, es_superusuario=false
--   rol_soporte       → puede_login=false, hereda=false, es_superusuario=false
--   rol_reportes      → puede_login=false, hereda=false, es_superusuario=false
--   app_web           → puede_login=true,  hereda=true,  limite_conexiones=20
--   admin_datos       → puede_login=true,  hereda=true,  limite_conexiones=5


-- -----------------------------------------------------------------------------
-- 2. Membresías: qué grupos hereda cada rol de login
-- -----------------------------------------------------------------------------

SELECT
    r.rolname     AS rol_login,
    g.rolname     AS grupo_heredado,
    m.admin_option AS es_admin_del_grupo
FROM pg_auth_members m
JOIN pg_roles r ON r.oid = m.member
JOIN pg_roles g ON g.oid = m.roleid
WHERE r.rolname IN ('app_web', 'admin_datos')
ORDER BY r.rolname, g.rolname;

-- Resultado esperado:
--   app_web     hereda → rol_app_lectura, rol_app_escritura
--   admin_datos hereda → rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes


-- -----------------------------------------------------------------------------
-- 3. Permisos a nivel de tabla por cada rol de grupo
--    Verificación central: ni más ni menos privilegios que los definidos en el design.
-- -----------------------------------------------------------------------------

SELECT
    grantee        AS rol,
    table_name     AS tabla,
    privilege_type AS privilegio
FROM information_schema.role_table_grants
WHERE grantee IN (
    'rol_app_lectura', 'rol_app_escritura',
    'rol_soporte', 'rol_reportes'
)
  AND table_schema = 'public'
ORDER BY grantee, table_name, privilege_type;

-- Resultado esperado (resumen):
--   rol_app_lectura   | categoria, producto, pedido, detalle_pedido | SELECT
--   rol_app_escritura | pedido                                       | SELECT, INSERT, UPDATE
--   rol_app_escritura | detalle_pedido                               | SELECT, INSERT, UPDATE, DELETE
--   rol_reportes      | categoria, producto, pedido, detalle_pedido  | SELECT
--   rol_soporte       | celular, pedido, detalle_pedido              | SELECT
--
-- IMPORTANTE: rol_soporte NO debe aparecer con SELECT sobre usuario en esta
-- consulta, porque su GRANT fue a nivel de columna (aparece en column_privileges).
-- Confirmar que la columna "tabla" no muestra "usuario" para rol_soporte aquí.


-- -----------------------------------------------------------------------------
-- 4. Permisos a nivel de COLUMNA — verificación del GRANT sobre usuario
--    Esta es la consulta clave para el permiso de columna de la Parte A.
-- -----------------------------------------------------------------------------

SELECT
    grantee        AS rol,
    table_name     AS tabla,
    column_name    AS columna,
    privilege_type AS privilegio
FROM information_schema.column_privileges
WHERE grantee = 'rol_soporte'
  AND table_name = 'usuario'
  AND table_schema = 'public'
ORDER BY column_name;

-- Resultado esperado — SOLO estas columnas (en orden alfabético):
--   rol_soporte | usuario | apellido_usuario    | SELECT
--   rol_soporte | usuario | created_at_usuario  | SELECT
--   rol_soporte | usuario | eliminado_usuario   | SELECT
--   rol_soporte | usuario | id_usuario          | SELECT
--   rol_soporte | usuario | mail_usuario        | SELECT
--   rol_soporte | usuario | nombre_usuario      | SELECT
--   rol_soporte | usuario | rol_usuario         | SELECT
--
-- ✗ contrasena_usuario NO debe aparecer en este resultado.
--   Si aparece, revisar roles.sql: hay un GRANT incorrecto que debe revocarse.


-- -----------------------------------------------------------------------------
-- 5. Verificación negativa: PUBLIC no debe tener acceso al schema
-- -----------------------------------------------------------------------------

SELECT
    grantee,
    privilege_type
FROM information_schema.usage_privileges
WHERE object_schema = 'public'
  AND object_name   = 'public'
  AND object_type   = 'SCHEMA'
  AND grantee       = 'PUBLIC';

-- Resultado esperado: 0 filas.
-- Si devuelve filas, el REVOKE del paso 9 de roles.sql no fue efectivo.


-- -----------------------------------------------------------------------------
-- 6. Prueba de restricción: confirmar que rol_soporte NO puede leer contrasena_usuario
--    Ejecutar conectado como un usuario que tenga rol_soporte (no como superusuario).
-- -----------------------------------------------------------------------------

-- Conectarse como admin_datos y hacer SET ROLE rol_soporte, luego:
-- SET ROLE rol_soporte;

-- Esta consulta DEBE fallar con: ERROR: permission denied for table usuario
-- (porque rol_soporte no tiene SELECT a nivel tabla, solo a nivel columna)
-- SELECT contrasena_usuario FROM usuario LIMIT 1;

-- Esta consulta SÍ debe funcionar (columnas autorizadas):
-- SELECT id_usuario, nombre_usuario, apellido_usuario, mail_usuario FROM usuario LIMIT 3;

-- =============================================================================
-- FIN DEL SCRIPT DE VERIFICACIÓN
-- =============================================================================
