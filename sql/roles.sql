-- =============================================================================
-- Food Store — Esquema de Roles y Permisos
-- Unidad 5, Parte A — Principio de Mínimo Privilegio
-- Motor: PostgreSQL 16+
--
-- Tablas del schema: categoria, producto, usuario, celular, pedido, detalle_pedido
-- Tipos ENUM: rol ('ADMIN','USUARIO'), estado_pedido, forma_pago
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 0. LIMPIEZA PREVIA — elimina roles si ya existen (útil para re-ejecutar)
--    En producción se omitiría; en desarrollo permite iterar sin errores.
-- -----------------------------------------------------------------------------

DO $$
DECLARE r text;
BEGIN
    -- Orden importante: primero los logins, después los grupos
    FOREACH r IN ARRAY ARRAY['app_web','admin_datos',
                             'rol_app_lectura','rol_app_escritura',
                             'rol_soporte','rol_reportes']
    LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('DROP OWNED BY %I', r);  -- quita permisos y defaults
            EXECUTE format('DROP ROLE %I', r);
        END IF;
    END LOOP;
END
$$;



-- -----------------------------------------------------------------------------
-- 1. CREACIÓN DE ROLES DE GRUPO (NOLOGIN: no pueden abrir conexiones directas)
-- -----------------------------------------------------------------------------

-- Lectura del catálogo y pedidos para la app web
CREATE ROLE rol_app_lectura
    NOLOGIN
    NOINHERIT
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE;

-- Escritura de pedidos, detalles y actualización de stock
CREATE ROLE rol_app_escritura
    NOLOGIN
    NOINHERIT
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE;

-- Lectura acotada para el equipo de soporte (sin datos sensibles)
CREATE ROLE rol_soporte
    NOLOGIN
    NOINHERIT
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE;

-- Lectura para informes de ventas y análisis
CREATE ROLE rol_reportes
    NOLOGIN
    NOINHERIT
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE;


-- -----------------------------------------------------------------------------
-- 2. CREACIÓN DE ROLES DE LOGIN
-- -----------------------------------------------------------------------------

-- Usuario de la aplicación web (hereda lectura + escritura)
CREATE ROLE app_web
    LOGIN
    INHERIT
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    CONNECTION LIMIT 20
    PASSWORD 'cambiar_antes_de_produccion_appweb';
-- ⚠ Cambiar la contraseña antes de usar en producción.

-- Usuario administrador / DBA
CREATE ROLE admin_datos
    LOGIN
    INHERIT
    NOSUPERUSER           -- no es superusuario: sus acciones siguen siendo auditables
    NOCREATEDB
    CREATEROLE            -- puede gestionar los roles del sistema
    CONNECTION LIMIT 5
    PASSWORD 'cambiar_antes_de_produccion_admin';
-- ⚠ Cambiar la contraseña antes de usar en producción.


-- -----------------------------------------------------------------------------
-- 3. ASIGNACIÓN DE MEMBRESÍAS
-- app_web hereda los grupos que necesita para operar.
-- admin_datos hereda todos los grupos para tareas de mantenimiento.
-- -----------------------------------------------------------------------------

GRANT rol_app_lectura   TO app_web;
GRANT rol_app_escritura TO app_web;

GRANT rol_app_lectura   TO admin_datos;
GRANT rol_app_escritura TO admin_datos;
GRANT rol_soporte       TO admin_datos;
GRANT rol_reportes      TO admin_datos;


-- -----------------------------------------------------------------------------
-- 4. ACCESO AL SCHEMA
-- Sin USAGE en el schema, ningún rol puede ver los objetos aunque tenga GRANTs.
-- -----------------------------------------------------------------------------

GRANT USAGE ON SCHEMA public
    TO rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes;


-- -----------------------------------------------------------------------------
-- 5. PERMISOS DE rol_app_lectura
-- Necesita leer el catálogo (categorías, productos) y el estado de los pedidos.
-- NO accede a usuario ni celular: la app no necesita mostrar esos datos al cliente.
-- -----------------------------------------------------------------------------

GRANT SELECT ON TABLE
    categoria,
    producto,
    pedido,
    detalle_pedido
TO rol_app_lectura;

-- Las secuencias las usa indirectamente al leer IDs generados
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO rol_app_lectura;


-- -----------------------------------------------------------------------------
-- 6. PERMISOS DE rol_app_escritura
-- Gestiona pedidos (ciclo completo) y descuenta stock al confirmar.
-- SELECT es necesario para leer el estado actual antes de modificar.
-- -----------------------------------------------------------------------------

-- Pedidos: ciclo completo (crear, actualizar estado, cancelar)
GRANT SELECT, INSERT, UPDATE ON TABLE pedido          TO rol_app_escritura;

-- Detalles: agregar, modificar cantidad, eliminar ítems de un pedido
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE detalle_pedido TO rol_app_escritura;

-- Producto: solo puede actualizar el stock (descuento al confirmar pedido)
-- Permiso a nivel de columna: no puede cambiar precio, nombre, etc.
GRANT UPDATE (stock_producto) ON TABLE producto       TO rol_app_escritura;

-- Necesita usar secuencias para generar IDs de nuevos pedidos y detalles
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO rol_app_escritura;


-- -----------------------------------------------------------------------------
-- 7. PERMISOS DE rol_soporte — PERMISO A NIVEL DE COLUMNA sobre usuario
--
-- El soporte necesita identificar al cliente (nombre, mail) y ver sus pedidos.
-- NO debe poder leer contrasena_usuario bajo ninguna circunstancia.
--
-- GRANT SELECT (columnas...) ON TABLE usuario permite al rol leer SOLO esas
-- columnas, bloqueando el acceso a contrasena_usuario a nivel del motor.
-- Esta es una restricción que no puede bypassearse con ninguna consulta.
-- -----------------------------------------------------------------------------

-- Columnas no sensibles de usuario: identificación del cliente y estado de cuenta
GRANT SELECT (
    id_usuario,
    nombre_usuario,
    apellido_usuario,
    mail_usuario,       -- necesario para contactar al cliente durante la incidencia
    rol_usuario,
    eliminado_usuario,
    created_at_usuario
) ON TABLE usuario TO rol_soporte;
-- ✗ contrasena_usuario: NO incluida. Soporte nunca necesita ver la contraseña.

-- Teléfonos de contacto del cliente (para llamar durante la incidencia)
GRANT SELECT ON TABLE celular TO rol_soporte;

-- Pedidos y detalles: para ver el historial de órdenes del cliente
GRANT SELECT ON TABLE pedido, detalle_pedido TO rol_soporte;


-- -----------------------------------------------------------------------------
-- 8. PERMISOS DE rol_reportes
-- Solo lectura sobre las tablas que alimentan los informes de ventas.
-- No necesita acceder a usuario ni celular (privacidad de datos).
-- -----------------------------------------------------------------------------

GRANT SELECT ON TABLE
    categoria,
    producto,
    pedido,
    detalle_pedido
TO rol_reportes;


-- -----------------------------------------------------------------------------
-- 9. REVOCACIÓN EXPLÍCITA DE PRIVILEGIOS PÚBLICOS
--
-- PostgreSQL otorga por defecto USAGE y CREATE al rol PUBLIC sobre el schema
-- public. Esto permite que cualquier usuario conectado acceda a los objetos.
-- Revocamos esos privilegios para que el acceso sea solo por los roles definidos.
-- -----------------------------------------------------------------------------

-- Nadie excepto los roles explícitos puede usar el schema
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Nadie puede crear tablas en el schema (solo el DBA que ejecuta migraciones)
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- Revocación explícita sobre las tablas sensibles
-- (refuerza que PUBLIC no heredó acceso a usuario ni celular)
REVOKE ALL ON TABLE usuario  FROM PUBLIC;
REVOKE ALL ON TABLE celular  FROM PUBLIC;
REVOKE ALL ON TABLE pedido   FROM PUBLIC;


-- -----------------------------------------------------------------------------
-- 10. ALTER DEFAULT PRIVILEGES
--
-- Garantiza que las tablas, vistas y secuencias que se creen en el futuro
-- en el schema public hereden automáticamente la política de permisos actual.
-- Sin esto, cada migración que cree una tabla nueva requeriría re-ejecutar GRANTs.
--
-- Se ejecuta en el contexto del propietario del schema (habitualmente el usuario
-- con el que se crean las tablas: postgres o el usuario de migraciones).
-- -----------------------------------------------------------------------------

-- Tablas futuras: lectura para rol_app_lectura y rol_reportes
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO rol_app_lectura;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO rol_reportes;

-- Tablas futuras transaccionales: escritura para rol_app_escritura
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO rol_app_escritura;

-- Secuencias futuras
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE ON SEQUENCES TO rol_app_lectura, rol_app_escritura;


-- =============================================================================
-- FIN DEL SCRIPT
--
-- Para verificar la correcta aplicación de permisos:
--   \du                                          → lista todos los roles
--   \dp usuario                                  → permisos sobre la tabla usuario
--   SELECT * FROM information_schema.role_table_grants WHERE grantee LIKE 'rol_%';
--   Ver también: sql/verificacion_permisos.sql
-- =============================================================================
