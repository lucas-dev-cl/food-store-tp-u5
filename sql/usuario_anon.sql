-- =============================================================================
-- Food Store — Anonimización de usuarios y verificación de equivalencia
-- Unidad 5, Parte D
-- Motor: PostgreSQL 16+
-- Ejecutar conectado como: postgres (o el propietario de las tablas)
--
-- Propósito:
--   1. Crear usuario_anon: copia de usuario donde los datos que identifican a la
--      persona (nombre, apellido, mail, contraseña) se reemplazan por valores
--      sintéticos deterministas, basados solo en id_usuario (sin azar: si se
--      ejecuta de nuevo, el resultado es idéntico).
--   2. Verificar que los resultados agregados sobre usuario_anon coinciden con
--      los de la tabla real usuario.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. CREACIÓN DE usuario_anon
--
-- Se reemplazan: nombre, apellido, mail y contraseña.
-- Se conservan sin cambios: id_usuario, rol_usuario, eliminado_usuario y
-- created_at_usuario, que son las columnas que usa el análisis agregado.
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS usuario_anon;

CREATE TABLE usuario_anon AS
SELECT
    id_usuario,
    'Nombre_'   || id_usuario                    AS nombre_usuario,
    'Apellido_' || id_usuario                    AS apellido_usuario,
    'usuario_'  || id_usuario || '@dominio.test' AS mail_usuario,
    '[REDACTADO]'                                AS contrasena_usuario,
    rol_usuario,
    eliminado_usuario,
    created_at_usuario
FROM usuario;

-- Comprobación rápida: no debe quedar ningún dato real en las columnas reemplazadas
SELECT * FROM usuario_anon ORDER BY id_usuario LIMIT 5;


-- -----------------------------------------------------------------------------
-- 2. CONSULTA DE AGREGACIÓN SOBRE usuario_anon
--    Cantidad de usuarios por rol y por mes de alta.
-- -----------------------------------------------------------------------------

SELECT
    rol_usuario,
    TO_CHAR(created_at_usuario, 'YYYY-MM') AS mes,
    COUNT(*) AS cantidad_usuarios
FROM
    usuario_anon
GROUP BY
    rol_usuario,
    TO_CHAR(created_at_usuario, 'YYYY-MM')
ORDER BY
    rol_usuario,
    mes;


-- -----------------------------------------------------------------------------
-- 3. CONSULTA EQUIVALENTE SOBRE LA TABLA REAL usuario
-- -----------------------------------------------------------------------------

SELECT
    rol_usuario,
    TO_CHAR(created_at_usuario, 'YYYY-MM') AS mes,
    COUNT(*) AS cantidad_usuarios
FROM
    usuario
GROUP BY
    rol_usuario,
    TO_CHAR(created_at_usuario, 'YYYY-MM')
ORDER BY
    rol_usuario,
    mes;


-- -----------------------------------------------------------------------------
-- 4. VERIFICACIÓN DE EQUIVALENCIA CON EXCEPT (en los dos sentidos)
--
-- Devuelve las combinaciones rol/mes que están en una tabla y no en la otra,
-- o que tienen distinto conteo.
-- Resultado esperado: 0 filas = los dos resultados son idénticos.
-- -----------------------------------------------------------------------------

(
    SELECT rol_usuario, TO_CHAR(created_at_usuario, 'YYYY-MM') AS mes, COUNT(*) AS cantidad_usuarios
    FROM usuario_anon
    GROUP BY rol_usuario, TO_CHAR(created_at_usuario, 'YYYY-MM')
    EXCEPT
    SELECT rol_usuario, TO_CHAR(created_at_usuario, 'YYYY-MM'), COUNT(*)
    FROM usuario
    GROUP BY rol_usuario, TO_CHAR(created_at_usuario, 'YYYY-MM')
)
UNION ALL
(
    SELECT rol_usuario, TO_CHAR(created_at_usuario, 'YYYY-MM'), COUNT(*)
    FROM usuario
    GROUP BY rol_usuario, TO_CHAR(created_at_usuario, 'YYYY-MM')
    EXCEPT
    SELECT rol_usuario, TO_CHAR(created_at_usuario, 'YYYY-MM'), COUNT(*)
    FROM usuario_anon
    GROUP BY rol_usuario, TO_CHAR(created_at_usuario, 'YYYY-MM')
);


-- -----------------------------------------------------------------------------
-- 5. CONTROL: MISMA CANTIDAD TOTAL DE FILAS EN AMBAS TABLAS
--    Sirve para confirmar que el resultado vacío del EXCEPT no se debe a que
--    una de las tablas esté vacía. Los dos números deben coincidir.
-- -----------------------------------------------------------------------------

SELECT
    (SELECT COUNT(*) FROM usuario)      AS filas_usuario,
    (SELECT COUNT(*) FROM usuario_anon) AS filas_usuario_anon;

-- =============================================================================
-- FIN DEL SCRIPT
-- =============================================================================
