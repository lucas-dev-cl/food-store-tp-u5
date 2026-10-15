## Decisión de contención

### 1. Evidencia en la que se basa la decisión

La reconstrucción del log (`docs/log_simulacro_anonimizado.txt`) y el contraste con lo ejecutado (sección anterior) establecen los siguientes hechos:

1. La cuenta de base de datos `soporte_user` abrió una sesión de 2,67 s desde `127.0.0.1` (PID 148848).
2. Dentro de esa sesión se hicieron seis llamadas consecutivas a `fn_autenticar` sobre el mismo mail, con seis contraseñas distintas.
3. Se leyó la tabla `usuario` completa (siete columnas no sensibles, incluidos nombre, apellido y mail de todos los clientes).
4. Se intentó `GRANT admin_datos TO soporte_user;` y el motor lo rechazó. La escalada de privilegios no prosperó.
5. El log nativo no registra el resultado de `fn_autenticar`, por lo que **no es posible determinar a partir del log si algún intento de autenticación fue exitoso**. Ante esa incertidumbre, en un caso real se debe asumir el escenario más desfavorable: que las credenciales de la cuenta fueron utilizadas por un tercero.

### 2. Medidas adoptadas

Las medidas se ordenan por urgencia.

#### Medida 1 (inmediata): rotar la contraseña de `soporte_user`

**Acción:**

```sql
ALTER ROLE soporte_user PASSWORD '<nueva_contraseña_larga_y_única>';
```

La nueva contraseña se genera aleatoriamente, se entrega solo a las personas que usan la cuenta y no se guarda en el repositorio. Si hay riesgo de que la sesión siga activa, se la cierra con `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = 'soporte_user';`.

**Justificación:**
- El log demuestra que la cuenta fue usada para leer datos personales de todos los clientes (hecho 3).
- Como el log no permite descartar que las credenciales estén comprometidas (hecho 5), la contraseña vigente debe considerarse expuesta.
- Es una medida de efecto inmediato, de bajo costo y reversible, que corta el acceso con la credencial actual sin interrumpir al resto de los roles.

#### Medida 2 (corto plazo): restringir los orígenes de conexión de `soporte_user`

**Acción:** en `pg_hba.conf` se agregan reglas específicas para `soporte_user`, ubicadas **antes** de la regla general (PostgreSQL aplica la primera coincidencia), que permiten la conexión solo desde el origen legítimo del equipo de soporte y rechazan el resto:

```
# tipo  base   usuario        origen                       método
host    all    soporte_user   <IP_ESTACION_SOPORTE>/32     scram-sha-256
host    all    soporte_user   0.0.0.0/0                    reject
host    all    soporte_user   ::/0                         reject
```

Luego se recarga la configuración con `SELECT pg_reload_conf();`.

**Justificación:**
- Una cuenta de soporte no necesita aceptar conexiones desde cualquier origen. Limitar el origen aplica el principio de mínimo privilegio a la red, igual que la Parte A lo aplicó a las tablas.
- Con esta regla, una credencial robada deja de ser suficiente: el atacante también necesitaría conectarse desde el origen autorizado.
- **No se propone bloquear la IP observada en el log.** El origen fue `127.0.0.1`, es decir, la propia máquina del servidor. Bloquearlo interrumpiría al resto de los servicios y herramientas legítimas, y además no explicaría cómo se llegó a esa máquina. Por eso la medida se plantea como una lista de orígenes permitidos para esta cuenta y no como un bloqueo puntual.
- Es una medida de defensa en profundidad y no sustituye a la Medida 1: restringe el origen, pero no invalida una contraseña ya expuesta.

### 3. Limitaciones de las medidas adoptadas

Estas dos medidas cortan el acceso con la credencial comprometida y reducen la superficie de ataque, pero **no resuelven**:

- **La exposición de datos ya ocurrida.** Los nombres y mails de todos los clientes fueron leídos. Rotar una contraseña no revierte eso.
- **El exceso de lectura de `soporte_user`.** Esta cuenta puede leer toda la tabla `usuario`, y su alcance excede lo necesario para atender una consulta de un cliente.
- **La falta de visibilidad en el log.** El log nativo no distingue intentos fallidos de exitosos en `fn_autenticar`.
- **El origen local del acceso.** Queda pendiente investigar cómo se accedió a la máquina.

Quedan identificadas como medidas complementarias a evaluar: forzar el cambio de contraseña de las cuentas de clientes cuyo mail aparece en los intentos, reducir el acceso de lectura de `soporte_user` a consultas por cliente, y registrar en una tabla de auditoría los resultados de `fn_autenticar`.

### 4. Declaración de responsabilidad

Esta decisión fue tomada por el equipo a partir de la evidencia del log y del contraste con lo realmente ejecutado. Las sugerencias de la IA se usaron como insumo para la reconstrucción; ninguna acción fue ejecutada automáticamente a partir de ellas. La IA, además, no propuso medidas concretas de contención, por lo que las medidas de esta sección son criterio propio del equipo.
