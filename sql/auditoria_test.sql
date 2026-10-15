-- =============================================================================
-- Food Store — Script de Prueba de Auditoría
-- Unidad 5, Parte B
--
-- Propósito: generar un fragmento de log PostgreSQL que sirva de evidencia
-- para la parte de auditoría. Ejecutar DESPUÉS de activar los parámetros
-- de log (ver docs/informe_auditoria.md).
--
-- Motor: PostgreSQL 16+
-- Ejecutar conectado como: app_web  (NO como superusuario)
-- =============================================================================

-- =============================================================================
-- OPERACIÓN 1: LECTURA (SELECT)
-- Con log_statement='mod' este SELECT NO aparece en el log.
-- Lo incluimos para documentar ese comportamiento: la auditoría 'mod' no
-- registra lecturas, solo escrituras. Para registrar lecturas se necesita
-- log_statement='all' o la extensión pgaudit.
-- =============================================================================

-- SELECT
--     p.id_producto,
--     p.nombre_producto,
--     p.precio_producto,
--     p.stock_producto,
--     c.nombre_categoria
-- FROM producto p
-- JOIN categoria c ON c.id_categoria = p.id_categoria
-- WHERE p.disponible_producto = TRUE
--   AND p.eliminado_producto  = FALSE
-- ORDER BY c.nombre_categoria, p.nombre_producto;

-- RESULTADO EN LOG: ninguna línea generada (log_statement='mod' no captura SELECT)


-- =============================================================================
-- OPERACIÓN 2: INSERCIÓN (INSERT)
-- Simula que un usuario hace un pedido nuevo.
-- Esta línea SÍ aparece en el log: LOG: statement: INSERT INTO pedido ...
-- =============================================================================

INSERT INTO pedido (
    fecha_pedido,
    estado_pedido,
    total_pedido,
    forma_pago_pedido,
    id_usuario
)
VALUES (
    NOW(),
    'PENDIENTE',
    3200.00,
    'TARJETA',
    2  -- id_usuario de Laura Martínez (usuario existente en data.sql)
);

-- RESULTADO EN LOG: una línea LOG con la sentencia completa.


-- =============================================================================
-- OPERACIÓN 3: ACTUALIZACIÓN (UPDATE)
-- Simula la confirmación del pedido recién creado.
-- =============================================================================

UPDATE pedido
SET
    estado_pedido = 'CONFIRMADO',
    total_pedido  = 3200.00
WHERE
    id_usuario    = 2
    AND estado_pedido = 'PENDIENTE'
    AND DATE(fecha_pedido) = CURRENT_DATE;

-- RESULTADO EN LOG: una línea LOG con la sentencia de actualización.


-- =============================================================================
-- OPERACIÓN 4: INTENTO DE ACCESO NO AUTORIZADO
-- app_web no tiene permiso para modificar usuario (solo rol_soporte tiene SELECT
-- de columnas específicas, y ningún rol de grupo tiene UPDATE sobre usuario).
-- Esta operación DEBE fallar con ERROR: permission denied for table usuario.
-- El error y la sentencia que lo causó quedan registrados en el log.
-- =============================================================================

-- Este UPDATE DEBE fallar (es el comportamiento correcto que queremos documentar):
UPDATE usuario
SET eliminado_usuario = TRUE
WHERE id_usuario = 2;

-- RESULTADO EN LOG:
--   LOG:   statement: UPDATE usuario SET eliminado_usuario = TRUE WHERE id_usuario = 2
--   ERROR: permission denied for table usuario
--   STATEMENT: UPDATE usuario SET eliminado_usuario = TRUE WHERE id_usuario = 2


-- =============================================================================
-- OPERACIÓN 5: CONEXIÓN FALLIDA — ejecutar desde TERMINAL (no desde psql)
--
-- Este paso genera una línea FATAL en el log de PostgreSQL.
-- No se puede ejecutar dentro de una sesión psql activa.
--
-- Ejecutar en la terminal del sistema operativo:
--
--   En Linux/Mac:
--     PGPASSWORD=contrasena_incorrecta psql \
--       -U app_web \
--       -d food_store \
--       -h 127.0.0.1 \
--       -p 5432
--
--   En Windows (PowerShell):
--     $env:PGPASSWORD="contrasena_incorrecta"
--     psql -U app_web -d food_store -h 127.0.0.1 -p 5432
--
--   O con usuario inexistente:
--     psql -U usuario_que_no_existe -d food_store -h 127.0.0.1
--
-- RESULTADO EN LOG:
--   LOG:   connection received: host=127.0.0.1 port=XXXXX
--   FATAL: password authentication failed for user "app_web"
-- =============================================================================
