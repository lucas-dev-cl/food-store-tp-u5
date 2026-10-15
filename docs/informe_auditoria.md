# Informe de Configuración de Auditoría — Food Store
## Unidad 5, Parte B — Base de Datos II

---

## 1. Objetivo

Activar el registro de auditoría básico en el servidor PostgreSQL 16 de desarrollo de Food Store,
de forma que queden documentadas las conexiones, desconexiones y operaciones de modificación de
datos (INSERT, UPDATE, DELETE). Este nivel mínimo permite responder las tres preguntas básicas
de cualquier investigación de incidente: **quién** hizo **qué** y **cuándo**.

---

## 2. Parámetros modificados en `postgresql.conf`

### Ruta del archivo de configuración

| Sistema operativo | Ruta habitual                                        |
|-------------------|------------------------------------------------------|
| Ubuntu/Debian     | `/etc/postgresql/16/main/postgresql.conf`            |
| Windows           | `C:\Program Files\PostgreSQL\16\data\postgresql.conf`|
| macOS (Homebrew)  | `/usr/local/var/postgresql@16/postgresql.conf`       |

### Bloque de configuración a agregar o modificar

```ini
# ============================================================
# AUDITORÍA BÁSICA — Food Store — Unidad 5
# ============================================================

# Registra cada inicio de sesión exitoso.
# Incluye: usuario, base de datos, dirección IP y puerto de origen.
log_connections = on

# Registra el cierre de cada sesión, junto con la duración total.
# Útil para detectar sesiones anormalmente largas o cortas.
log_disconnections = on

# Nivel de registro de sentencias:
#   'none' → no registra ninguna sentencia
#   'ddl'  → solo CREATE, ALTER, DROP
#   'mod'  → DDL + INSERT, UPDATE, DELETE, TRUNCATE  ← usamos este
#   'all'  → todo, incluido SELECT (muy verboso; solo para debug)
# 'mod' es el balance correcto para auditoría de modificaciones
# sin saturar el log con miles de SELECT de la app.
log_statement = 'mod'

# Formato de cada línea del log.
# %t = timestamp con zona horaria
# %p = PID del proceso backend de PostgreSQL
# %u = nombre de usuario que ejecutó la sentencia
# %d = nombre de la base de datos
# %r = dirección IP y puerto del cliente (ej: 127.0.0.1:54312)
#       o [local] si la conexión es por socket Unix
log_line_prefix = '%t [%p] %u@%d %r '

# Destino y rotación del log
log_destination = 'stderr'
logging_collector = on
log_directory = 'pg_log'                    # relativo a PGDATA
log_filename = 'postgresql-%Y-%m-%d.log'    # un archivo por día
log_rotation_age = 1d                       # nueva rotación cada día
log_rotation_size = 0                       # sin límite de tamaño

# Nivel mínimo de mensajes a registrar
log_min_messages = warning
log_min_error_statement = error
```

---

## 3. Cómo aplicar los cambios

### Opción A — Recarga sin reinicio (para `log_connections`, `log_statement`)

La mayoría de los parámetros de log se pueden aplicar sin reiniciar el servidor:

```bash
# Como usuario del sistema operativo con permisos de administración:
sudo systemctl reload postgresql

# O desde dentro de psql, conectado como superusuario:
SELECT pg_reload_conf();
```

### Opción B — Reinicio completo (necesario si se activa `logging_collector`)

`logging_collector` requiere reinicio porque arranca un proceso separado:

```bash
sudo systemctl restart postgresql
```

### Verificar que los parámetros tomaron efecto

```sql
-- Ejecutar en psql (cualquier usuario):
SHOW log_connections;
SHOW log_disconnections;
SHOW log_statement;
SHOW log_line_prefix;
SHOW logging_collector;
```

---

## 4. Análisis del log capturado

*(El fragmento completo está en `docs/log_auditoria_prueba.txt`)*

### 4a. Lectura del log: quién, qué, cuándo, desde dónde

El log generado al ejecutar `sql/auditoria_test.sql` como `app_web` permite responder:

| Pregunta        | Información disponible                                                    | Ejemplo del log                                 |
|-----------------|---------------------------------------------------------------------------|-------------------------------------------------|
| **Quién**       | Nombre del usuario (`%u` en el prefijo)                                   | `app_web@food_store`                            |
| **Qué**         | Sentencia SQL completa (para operaciones `mod`) o tipo de evento          | `LOG: statement: INSERT INTO pedido (...)`      |
| **Cuándo**      | Timestamp con zona horaria en cada línea (`%t`)                           | `2026-10-12 14:30:01.892 -03`                   |
| **Desde dónde** | Dirección IP y puerto del cliente (`%r`)                                  | `127.0.0.1:52301` o `[local]`                   |

**Evento destacado del log:** La Operación 4 (intento de UPDATE sobre `usuario`) genera
dos líneas clave:
```
LOG:   statement: UPDATE usuario SET eliminado_usuario = TRUE WHERE id_usuario = 2
ERROR: permission denied for table usuario
```
Esto confirma que el esquema de permisos de la Parte A funciona: la acción fue intentada,
quedó registrada, y el motor la rechazó. Un analista puede ver exactamente qué usuario,
desde qué IP y a qué hora intentó modificar una tabla a la que no tenía acceso.

### 4b. Qué queda fuera del alcance del mecanismo nativo

El log nativo de PostgreSQL con `log_statement='mod'` registra la **sentencia completa**,
pero **no el impacto fila a fila**. Ejemplos de lo que no captura:

- Cuáles filas específicas fueron modificadas por un `UPDATE` y cuáles eran sus valores
  antes y después del cambio.
- Cuántas filas afectó realmente una operación (el log registra la sentencia, no el rowcount).
- Lecturas (`SELECT`): con `log_statement='mod'` no se registra ningún SELECT, lo que
  significa que una extracción masiva de datos (ej: `SELECT * FROM usuario`) pasaría
  desapercibida en el log.

Para ese nivel de granularidad se necesitaría la extensión **`pgaudit`**, que puede
configurarse para registrar eventos a nivel de objeto (qué tabla, qué operación, qué
sesión) y es compatible con marcos de cumplimiento normativo como SOC 2 o PCI-DSS.

### 4c. El log como activo sensible

**¿El archivo de log es en sí mismo un activo sensible?**

Sí, y debe tratarse con el mismo nivel de protección que la base de datos. El log de
PostgreSQL con `log_statement='mod'` puede contener sentencias SQL completas, incluyendo
los valores literales de los datos modificados. En el caso de Food Store, una sentencia
como `INSERT INTO pedido (..., id_usuario) VALUES (..., 2)` expone información del
comportamiento de compra del usuario. Si se usara `log_statement='all'`, el log contendría
también todos los SELECT, potencialmente exponiendo datos de sesión, tokens de autenticación
pasados como parámetros, o correos electrónicos de clientes.

**¿Quién debería poder leerlo y con qué permisos?**

El archivo de log debe ser legible únicamente por el usuario del sistema operativo que
ejecuta el proceso de PostgreSQL (habitualmente `postgres`) y por administradores de
infraestructura que realicen auditorías formales con autorización documentada. A nivel
de sistema operativo, los permisos recomendados son `640` (lectura solo para propietario
y grupo `postgres`) sobre los archivos, y `750` sobre el directorio `pg_log`. Ningún
usuario de aplicación —como `app_web`— debe tener acceso al sistema de archivos donde
residen los logs.

---

## 5. Referencias

- [PostgreSQL 16 — Error Reporting and Logging](https://www.postgresql.org/docs/16/runtime-config-logging.html)
- [pgaudit — PostgreSQL Audit Extension](https://www.pgaudit.org/)
- [PostgreSQL 16 — log_line_prefix format](https://www.postgresql.org/docs/16/runtime-config-logging.html#GUC-LOG-LINE-PREFIX)
