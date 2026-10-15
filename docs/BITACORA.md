# BITÁCORA DE USO DE IA — Food Store TP Unidad 5

## Herramientas de IA utilizadas

- **OpenCode**: Partes A y B (registros 1 a 7), reconstrucción del log en la Parte C (registro 12) y consultas de la Parte D (registro 14).
- **Claude (asistente de chat)**: ayuda para reconstruir las funciones de autenticación, armar el script del simulacro, anonimizar el log, redactar informes (registros 8 a 11, 13 y 15). Se declara aquí porque no es OpenCode.

---

## PARTE A — Diseño e implementación de roles y permisos

| # | Prompt enviado a la IA (OpenCode) | Respuesta relevante recibida | Validación / corrección humana aplicada |
|---|-----------------------------------|------------------------------|-----------------------------------------|
| 1 | "Generá un script SQL de roles para PostgreSQL 16 con CREATE ROLE, GRANT y REVOKE para una app de delivery llamada Food Store. Los roles son: rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes (grupos, NOLOGIN), y app_web, admin_datos (login). Aplicar mínimo privilegio." | OpenCode generó el script base con los seis roles y sus atributos correctamente. Sin embargo, para `rol_app_lectura` propuso `GRANT ALL ON ALL TABLES IN SCHEMA public TO rol_app_lectura`, justificando que "simplifica el mantenimiento a largo plazo porque no hay que recordar qué tablas se crearon". También sugirió `GRANT SUPERUSER TO admin_datos` para "facilitar la administración". | **RECHAZADO en ambos casos.** `GRANT ALL` otorga INSERT, UPDATE, DELETE y TRUNCATE a un rol cuya única función es leer datos; cualquier error o compromiso de ese rol podría modificar la base. El argumento de conveniencia no justifica violar el principio de mínimo privilegio. `GRANT SUPERUSER` fue rechazado porque un superusuario en PostgreSQL puede bypassear cualquier control de acceso y sus acciones no pueden auditarse de la misma manera; `admin_datos` cumple su función con `CREATEROLE` y acceso heredado a los grupos. Se reemplazaron ambas sugerencias por GRANTs específicos por tabla y operación. |
| 2 | "¿Cómo restrinjo el acceso de rol_soporte a solo ciertas columnas de la tabla usuario en PostgreSQL? La tabla tiene: id_usuario, nombre_usuario, apellido_usuario, mail_usuario, contrasena_usuario, rol_usuario, eliminado_usuario, created_at_usuario." | OpenCode explicó correctamente la sintaxis `GRANT SELECT (col1, col2, ...) ON TABLE tabla TO rol;` y aclaró que este permiso es incompatible con un `GRANT SELECT ON TABLE` previo a nivel tabla (que habría que revocar primero). Además sugirió incluir `contrasena_usuario` en la lista "para que soporte pueda verificar si el cliente tiene contraseña configurada". | **ACEPTADO PARCIALMENTE.** La sintaxis de columna es correcta y se aplicó. La sugerencia de incluir `contrasena_usuario` fue **rechazada**: el hash de contraseña no aporta información útil para resolver una incidencia de soporte, y exponer ese campo aumenta la superficie de ataque sin ningún beneficio operativo. Se excluyó explícitamente. |
| 3 | "Cómo verificar con SQL que rol_soporte solo puede acceder a las columnas autorizadas de usuario y no a contrasena_usuario." | OpenCode generó correctamente la consulta a `information_schema.column_privileges` para ver permisos a nivel de columna. También sugirió usar `\dp usuario` en psql. | **ACEPTADO con adición.** Se incluyó la consulta a `information_schema.role_table_grants` para confirmar que `rol_soporte` no tiene `SELECT` a nivel tabla sobre `usuario` (lo que anularía la restricción de columna). OpenCode no había mencionado ese punto; el equipo lo identificó al revisar la documentación de PostgreSQL. |
| 4 | "Mostrá cómo usar ALTER DEFAULT PRIVILEGES para que las tablas futuras hereden los permisos de los roles definidos." | OpenCode generó el bloque `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO rol_app_lectura` (de nuevo con `ALL`). También aclaró que el comando debe ejecutarse como el usuario propietario del schema. | **RECHAZADO (el GRANT ALL).** Se reemplazó por `GRANT SELECT` específico para cada rol. La observación sobre el propietario del schema es correcta y se documentó en el script. **Revisión posterior (Parte E):** al releer `roles.sql` se verificó que para `rol_app_escritura` quedó `SELECT, INSERT, UPDATE, DELETE` sobre todas las tablas futuras. No es `ALL`, pero sigue siendo más amplio que la política por tabla definida en el design (por ejemplo, `pedido` no tiene `DELETE`). Queda como mejora pendiente. |

### Verificación de la Parte A realizada por el equipo

Además de listar permisos con `pg_roles`, `pg_auth_members` e `information_schema`, se hicieron pruebas de comportamiento con `SET ROLE`:

- Como `app_web`: `SELECT` sobre `producto` funciona y sobre `usuario` da "permiso denegado".
- Como `app_web`: `GRANT admin_datos TO app_web` falla con "Sólo los roles con la opción ADMIN en el rol «admin_datos» pueden otorgar este rol".
- Como `rol_soporte`: la lectura de columnas autorizadas funciona y la de `contrasena_usuario` falla.

Se detectaron inconsistencias entre la especificación de Kiro y `roles.sql` (por ejemplo, `design.md` D-01 asigna `DELETE` sobre `pedido` a `rol_app_escritura` pero la matriz D-04 y el script no, y RF-03 y D-02 indican que `admin_datos` puede leer `contrasena_usuario` pero en el script no puede). Se corrige la especificación para que ningún rol pueda leer esa columna.

---

## PARTE B — Activación y prueba de la auditoría

| # | Prompt enviado a la IA (OpenCode) | Respuesta relevante recibida | Validación / corrección humana aplicada |
|---|-----------------------------------|------------------------------|-----------------------------------------|
| 5 | "¿Qué parámetros de postgresql.conf debo activar en PostgreSQL 16 para auditar conexiones, desconexiones y operaciones de modificación de datos?" | OpenCode listó `log_connections`, `log_disconnections` y `log_statement='mod'`. También sugirió `log_min_duration_statement = 0` para registrar todas las sentencias con su tiempo de ejecución, y `log_statement = 'all'` "para no perder ningún evento de seguridad". | **ACEPTADO PARCIALMENTE.** `log_connections` y `log_disconnections` se aplicaron tal cual. `log_statement='all'` fue rechazado para uso general: generaría un volumen de log inmanejable y dificultaría encontrar los eventos relevantes. `log_min_duration_statement = 0` también fue descartado porque mezcla información de rendimiento con información de seguridad. Para auditoría de modificaciones, `log_statement='mod'` es el balance correcto. (Ver registro 9: en la Parte C `all` se activó de forma temporal y justificada.) |
| 6 | "Qué valor de log_line_prefix me conviene para identificar quién, desde dónde y cuándo en cada línea del log de PostgreSQL 16." | OpenCode sugirió `log_line_prefix = '%m [%p]: '` (timestamp con milisegundos y PID). No incluyó el usuario ni la base de datos ni la IP de origen. | **CORREGIDO.** Se amplió a `'%t [%p] %u@%d %r '` para incluir el usuario (`%u`), la base (`%d`) y la dirección IP del cliente (`%r`). Sin `%r`, el log no responde desde dónde; sin `%u`, no identifica al usuario que ejecutó la sentencia. La sugerencia original era válida para un log de rendimiento, no para auditoría. |
| 7 | "Generá un fragmento de log PostgreSQL 16 simulado que muestre: conexión exitosa, INSERT, UPDATE, error de permiso, desconexión y dos conexiones fallidas. Usar el log_line_prefix definido." | OpenCode generó un fragmento de log con formato aparentemente correcto. Sin la línea `STATEMENT:` posterior al `ERROR:`, que se agregó a mano. | **Primera validación (insuficiente):** se corrigió solo la línea `STATEMENT:` y se entregó el fragmento. **Corrección posterior (Parte E):** el fragmento era inventado y no cumplía el requisito de evidencia real. Se lo reemplazó por el log real capturado el 2026-10-13 en PostgreSQL 18 (Windows), ejecutando `auditoria_test.sql` como `app_web` y dos logins fallidos desde terminal. Ver "Caso más significativo" más abajo. |

---

## PARTE C — Simulacro de incidente de acceso indebido

| # | Prompt enviado a la IA | Respuesta relevante recibida | Validación / corrección humana aplicada |
|---|------------------------|------------------------------|-----------------------------------------|
| 8 | (Claude) "Las funciones fn_autenticar y fn_resetear_password del enunciado no existen en mi base. Las contraseñas se guardan con bcrypt (`$2a$12$...`). Generalas para PostgreSQL." | Dos funciones PL/pgSQL `SECURITY DEFINER` con `SET search_path`, usando `crypt()` de la extensión pgcrypto, con `REVOKE ... FROM PUBLIC` y `GRANT EXECUTE` puntual (`fn_autenticar` para `app_web` y `soporte_user`, `fn_resetear_password` solo para `admin_datos`). | **Reconstrucción declarada** (el enunciado lo permite). `pgcrypto` no estaba instalada y se instaló con `CREATE EXTENSION`. Se probó: contraseña correcta devuelve `true`, incorrecta `false`, mail inexistente `false`. Como `soporte_user`: puede autenticar, pero no leer `contrasena_usuario` ni ejecutar `fn_resetear_password`. Se creó un cliente de prueba (`cliente.prueba@example.com`) porque no se conocía la contraseña de los usuarios reales. Decisión del equipo: dar `EXECUTE` de `fn_autenticar` a `soporte_user` para que el simulacro use una sola sesión. |
| 9 | (Claude) "app_web no puede leer usuario. ¿Qué rol uso como víctima del simulacro y qué log_statement necesito para capturar la lectura masiva?" | Crear `soporte_user` (login, sin privilegios especiales) miembro de `rol_soporte`, y poner `log_statement = 'all'`, porque con `mod` los `SELECT` no se registran. | Se creó `soporte_user`. Antes de ejecutar el simulacro el equipo detectó que `log_statement` seguía en `mod`; se cambió con `ALTER SYSTEM`, se recargó y se confirmó con `SHOW`. Es una excepción justificada a la decisión del registro 5: la secuencia del simulacro es casi toda `SELECT`. Debe volver a `mod` al terminar. |
| 10 | (Claude) "Armá un script SQL con la secuencia del enunciado: intentos fallidos, login exitoso, lectura masiva y escalamiento." | Script `simulacro_incidente.sql` de 4 etapas, para ejecutar con psql como `soporte_user`. | Se ejecutó con psql (no con `SET ROLE`) para que el log registre a `soporte_user`. Se verificó la salida: 5 resultados `f`, 1 `t`, tabla de usuarios y, en la etapa 4, `ERROR: se ha denegado el permiso para otorgar el rol «admin_datos»`. El escalamiento falló, por lo que no hay hallazgo en el esquema de permisos. Riesgo residual: la lectura masiva funcionó. Se usaron columnas explícitas porque `SELECT *` falla por `contrasena_usuario`. |
| 11 | (Claude) Se pegó el tramo del log del simulacro y se pidió anonimizarlo. | Reemplazos: mail por `usuario_a@dominio.test`, contraseñas por `[PASSWORD_1]` a `[PASSWORD_6]`, y corrección de caracteres rotos por codificación. | El log original contenía solo datos del cliente de prueba (sintético), no datos reales. Se verificó que los reemplazos fueran consistentes en todas las líneas. La tabla de equivalencias se guardó fuera del repositorio. Se advirtió que reemplazar las contraseñas le quita a la IA una pista (que eran valores distintos y consecutivos). |
| 12 | (OpenCode) "Este es un fragmento de log de PostgreSQL. Reconstruí qué ocurrió, en orden cronológico, e indicá una hipótesis de contención." (seguido del log anonimizado, sin más contexto) | Cronología correcta de 6 llamadas a `fn_autenticar`, lectura de `usuario`, `GRANT admin_datos` rechazado y desconexión. Hipótesis: script de fuerza bruta más escalada de privilegios desde una cuenta de soporte. Alternativas: pentest o prueba propia. No propuso medidas concretas de contención. | Contraste completo en `docs/informe_incidente.md`. Acertó en horas, PID, usuario, origen, orden y rechazo del `GRANT`, y fue prudente al decir que el log no registra resultados. Excedió la evidencia al hablar de "fuerza bruta" (6 intentos sobre una cuenta) y de intención de "enumerar usuarios y roles". Omitió el significado del origen `127.0.0.1` (acceso local) y no entregó medidas de contención. No se ejecutó ninguna acción a partir de su respuesta. |
| 13 | (Claude) "Ayudame a redactar la decisión de contención con rotar la contraseña de soporte_user y restringir el origen." | Borrador de `docs/decision_contencion.md` con justificación basada en la evidencia, limitaciones y declaración de responsabilidad. | Las medidas las eligió el equipo. Se decidió no proponer bloquear la IP del log, porque era `127.0.0.1` y bloquearla cortaría el servicio legítimo; en su lugar, lista de orígenes permitidos para `soporte_user`. Se dejaron explícitas las limitaciones: los datos ya leídos, el exceso de lectura de `soporte_user` y la falta de registro de resultados de `fn_autenticar`. |

---

## PARTE D — Protección de datos personales

| # | Prompt enviado a la IA | Respuesta relevante recibida | Validación / corrección humana aplicada |
|---|------------------------|------------------------------|-----------------------------------------|
| 14 | (OpenCode) Se describió la estructura de `usuario_anon` (sin datos reales) y se pidió una consulta que cuente usuarios por `rol_usuario` y por mes de `created_at_usuario`, más la consulta equivalente sobre `usuario`. | Dos consultas idénticas salvo la tabla, usando `TO_CHAR(created_at_usuario, 'YYYY-MM')`, `GROUP BY` y `ORDER BY rol_usuario, mes`. | Se revisó que ninguna tuviera filtros distintos. Se ejecutaron ambas y se comprobó con `EXCEPT` en los dos sentidos que el resultado es de **0 filas**, es decir, idénticas. No se detectó error de la IA en esta parte. Evidencia en `docs/verificacion_equivalencia.md`. |
| 15 | (Claude) "Generá un script que cree usuario_anon con datos sintéticos deterministas." | `CREATE TABLE usuario_anon AS SELECT ...` reemplazando nombre, apellido, mail y contraseña por valores basados en `id_usuario`, y conservando `rol_usuario`, `eliminado_usuario` y `created_at_usuario`. | Se verificó que las columnas usadas por la agregación no se alteraron, y que el resultado agregado coincide con el de la tabla real. |

---

## PARTE E — Cierre

### Caso más significativo de error o imprecisión de la IA

**Registro 7: log de auditoría "simulado" generado por la IA.**

La IA produjo un fragmento de log con formato convincente, y la primera revisión del equipo solo corrigió un detalle (la línea `STATEMENT:`), dando el resto por válido. El problema de fondo era otro: el enunciado pide evidencia real de que la auditoría funciona, y un texto generado por la IA no demuestra nada. Además contenía errores que el motor real no comete.

Se detectó al ejecutar `auditoria_test.sql` como `app_web` y dos logins fallidos, y comparar contra el log que PostgreSQL escribió de verdad:

- En el log real, la línea `conexión recibida` aparece como `[desconocido]@[desconocido]`, porque el servidor todavía no sabe quién se conecta. El inventado ya mostraba `app_web@food_store`.
- Para un usuario inexistente, el log inventado decía `role does not exist`. El real dice `la autentificación password falló` y recién en el `DETALLE` indica `No existe el rol`. Al cliente, el servidor le responde lo mismo con un usuario real o inexistente.
- Difieren la base (`tpi_db` y no `food_store`), la versión (PostgreSQL 18), el idioma y el formato de la IP.

Se reemplazó el archivo por el log real. La lección es que, en seguridad, una salida plausible no es evidencia: hay que generarla y comprobarla.

Caso secundario: en el registro 12, OpenCode calificó el patrón como "fuerza bruta" con intención de enumeración, algo que el log no sustenta, y no propuso contención concreta.
