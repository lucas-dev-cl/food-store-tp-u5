# Verificación de equivalencia: `usuario_anon` vs `usuario`

## 1. Objetivo

Demostrar que anonimizar la tabla `usuario` no distorsiona los resultados agregados. Para eso se comparó la misma consulta de agregación (cantidad de usuarios por rol y por mes de alta) sobre la tabla anonimizada y sobre la tabla real.

## 2. Anonimización aplicada

El script `sql/usuario_anon.sql` crea `usuario_anon` reemplazando de forma determinista los datos que identifican a la persona (nombre, apellido, mail y contraseña) por valores sintéticos que dependen solo de `id_usuario`. Las columnas `rol_usuario`, `eliminado_usuario` y `created_at_usuario` se conservan sin cambios, porque son las que usa el análisis.

## 3. Consultas generadas por OpenCode

Sobre `usuario_anon`:

```sql
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
```

Sobre `usuario` (equivalente):

```sql
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
```

Revisión del equipo: las dos consultas son idénticas salvo por el nombre de la tabla. Ninguna tiene filtros adicionales que las diferencien.

## 4. Resultados

Ambas consultas se ejecutaron en DBeaver. Los resultados se adjuntan lado a lado a continuación.

| `usuario_anon` | `usuario` |
|---|---|
| *(pegar aquí el resultado o una captura)* | *(pegar aquí el resultado o una captura)* |

## 5. Comprobación con `EXCEPT`

Para demostrar la equivalencia y no solo afirmarla, se comparó el resultado de ambas consultas en los dos sentidos (A menos B, y B menos A):

```sql
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
```

**Resultado: 0 filas.** No existe ninguna combinación de rol y mes que difiera entre las dos tablas: los agrupamientos y los conteos son idénticos.

## 6. Conclusión

Los resultados agregados de `usuario_anon` y `usuario` son equivalentes. Esto es esperable, porque el proceso de anonimización solo reemplazó los datos identificatorios y dejó intactas las columnas que usa la agregación. Queda demostrado que se puede analizar la base con una IA usando la tabla anonimizada sin exponer datos reales y sin distorsionar el resultado.

## 7. Información que no debe salir hacia una IA sin anonimizar

No deben salir hacia una IA, sin anonimizar, los nombres, apellidos, mails y teléfonos de los clientes, ni los hashes de `contrasena_usuario`. Tampoco los logs de auditoría, porque con `log_statement = 'all'` las sentencias de `fn_autenticar` guardan mails y contraseñas en texto plano, como se vio en el simulacro de la Parte C. En cambio, la estructura de las tablas y los resultados agregados pueden compartirse, porque no identifican a nadie.
