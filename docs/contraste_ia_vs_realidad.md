## Contraste entre la reconstrucción de la IA y lo efectivamente ejecutado

### 1. Referencia: qué se ejecutó realmente

Script `sql/simulacro_incidente.sql`, ejecutado con `psql` como `soporte_user` desde `127.0.0.1`, en una única sesión (PID 148848) de 2,674 s, el 2026-10-14 entre las 21:53:18 y las 21:53:21:

| Etapa | Acción | Resultado real |
|---|---|---|
| 1 | 5 llamadas a `fn_autenticar` con contraseñas incorrectas (`intento1` a `intento5`) | 5 × `false` (sin error) |
| 2 | 1 llamada a `fn_autenticar` con la contraseña correcta | `true` |
| 3 | `SELECT` de 7 columnas no sensibles sobre toda la tabla `usuario` | Ejecutado con éxito |
| 4 | `GRANT admin_datos TO soporte_user;` | **Falló**: permiso denegado (sin opción ADMIN) |

Condiciones del log entregado a la IA: tramo recortado (sin las líneas de conexión/autenticación), con el mail reemplazado por `usuario_a@dominio.test` y las seis contraseñas reemplazadas por `[PASSWORD_1]` a `[PASSWORD_6]`.

### 2. Qué acertó la IA

| Afirmación de la IA | Verificación |
|---|---|
| Una sola sesión, PID 148848, `soporte_user`, desde 127.0.0.1 | Correcto |
| Ventana 21:53:18 a 21:53:21, sesión de 2,67 s | Correcto |
| 6 llamadas a `fn_autenticar` con el mismo mail y 6 contraseñas distintas | Correcto (la distinción surge de los marcadores `[PASSWORD_N]`) |
| Ritmo de ~2 s para 6 intentos, compatible con un script y no con una persona | Correcto: se ejecutó con `psql -f` |
| Luego un `SELECT` sobre `usuario` con las columnas indicadas | Correcto |
| Luego `GRANT admin_datos TO soporte_user;` como intento de auto-otorgarse un rol | Correcto |
| El motor lo rechazó por falta de opción ADMIN sobre `admin_datos` | Correcto (consta en `ERROR` y `DETALLE`) |
| La escalada no prosperó y la sesión se cerró | Correcto |
| Declaró que no puede saber si algún intento tuvo éxito, porque el log no registra resultados | Correcto y prudente |
| `soporte_user` lee la tabla `usuario` con más amplitud de la necesaria | Coincide con el riesgo residual identificado por el equipo |

### 3. Qué omitió la IA

1. **Qué intentos fallaron y cuál tuvo éxito.** No lo indicó, y con razón: `fn_autenticar` devuelve `false` sin lanzar error, por lo que el log no distingue un fallo de un acierto. Es una limitación del mecanismo de auditoría, no un error de la IA, pero tiene una consecuencia: el hecho más grave del incidente (el sexto intento fue válido, es decir, hubo credenciales comprometidas) es invisible en el log.
2. **Medidas concretas de contención.** El pedido incluía una hipótesis de contención y la respuesta no propuso ninguna acción (rotar la contraseña de `soporte_user`, forzar cambio de contraseñas, restringir origen en `pg_hba.conf`, reducir permisos de lectura). Solo sugirió "confirmar con quien tenga acceso a esa cuenta".
3. **Significado del origen 127.0.0.1.** Mencionó la IP, pero no extrajo la consecuencia: la conexión es local, por lo que el actor tenía acceso a la propia máquina del servidor o a un túnel/aplicación en ella, y no era un atacante externo directo.
4. **Que el tramo comienza a mitad de sesión.** No advirtió que faltan las líneas de conexión y autenticación, por lo que no se puede saber cómo se abrió la sesión.

### 4. Afirmaciones que el log no sustenta, o sustenta solo en parte

| Afirmación | Evaluación |
|---|---|
| "Fuerza bruta" | **Excede la evidencia.** Son 6 intentos sobre una única cuenta; no hay volumen ni variedad de objetivos propios de una fuerza bruta. A lo sumo, adivinanza de contraseña. |
| "Intento automatizado (script)" | Inferencia razonable a partir de los intervalos de ~0,5 s. Resultó correcta, pero el log no permite descartar que una persona pegara un lote de sentencias. |
| "Está relevando usuarios y roles" / "enumeración" | **Intención no sustentada.** El log muestra la sentencia, no el propósito. |
| "Cuenta de soporte con acceso directo a la base" | Deducido del nombre del rol; el log no confirma su función. |
| Alternativas "pentest, compañero o docente" | Especulación declarada como tal; coincide con la realidad (simulacro propio) pero sin base en el log. |

No se detectaron afirmaciones directamente contradichas por el log (fechas, horas, PID, usuario y errores fueron correctos).

### 5. Valoración

La reconstrucción cronológica fue precisa y la IA mostró cautela correcta sobre lo que el log no registra. Sus debilidades están en la interpretación: etiquetó el patrón como fuerza bruta con intención de enumeración sin evidencia suficiente, y no entregó medidas de contención concretas. La limitación más relevante, que el log no registra resultados, nos lleva a recomendar mejorar la auditoría (por ejemplo, que `fn_autenticar` registre los intentos fallidos en una tabla de auditoría o con `RAISE WARNING`), porque con el mecanismo nativo la IA no pudo distinguir 5 fallos de 1 éxito.
