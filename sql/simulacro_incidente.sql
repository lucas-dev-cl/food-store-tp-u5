-- simulacro_incidente.sql
-- Ejecutar con: psql -U soporte_user -d tpi_db -h 127.0.0.1 -f simulacro_incidente.sql

ALTER SYSTEM SET log_statement = 'all';
SELECT pg_reload_conf();
SHOW log_statement;

\echo '== Etapa 1: intentos fallidos contra fn_autenticar =='
SELECT fn_autenticar('cliente.prueba@example.com', 'intento1');
SELECT fn_autenticar('cliente.prueba@example.com', 'intento2');
SELECT fn_autenticar('cliente.prueba@example.com', 'intento3');
SELECT fn_autenticar('cliente.prueba@example.com', 'intento4');
SELECT fn_autenticar('cliente.prueba@example.com', 'intento5');

\echo '== Etapa 2: login exitoso =='
SELECT fn_autenticar('cliente.prueba@example.com', 'Prueba#2026');

\echo '== Etapa 3: lectura masiva de usuario =='
SELECT id_usuario, nombre_usuario, apellido_usuario, mail_usuario,
       rol_usuario, eliminado_usuario, created_at_usuario
FROM usuario;

\echo '== Etapa 4: intento de escalamiento =='
GRANT admin_datos TO soporte_user;