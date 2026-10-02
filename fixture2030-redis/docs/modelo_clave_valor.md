# Modelo clave/valor — Caché de usuarios y sesiones (Hito 7)

## Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II

Cada clave de este documento existe por un patrón de `patrones_de_acceso.md`.
Los valores de TTL son **decisiones del grupo**, sin un criterio numérico externo.

---

## 1. Convención de nombres

```
<propósito>:<dominio>:<id>[:<detalle>]
```

- Minúsculas, en español, `:` como separador. Es una convención humana; Redis no crea
  carpetas.
- **Propósito** primero: `sesion` (estado propio de Redis) o `cache` (copia de otro
  módulo, descartable). Quien lee la clave sabe si puede borrarla sin perder verdad.
- **Clave estable:** el `<id>` es siempre el identificador de la fuente de verdad
  (`P-001`, `ARG`), nunca un nombre editable.
- **Alcance explícito:** el contador de visitas incluye partido y día; no es un
  contador global.
- **Sin secretos:** ninguna clave contiene tokens, correos ni IP. La sesión
  se identifica con un id de sesión opaco.
- **Excepción:** el contador de visitas sigue la forma `partido:<id>:visitas`, con la fecha al final: `partido:<id>:visitas:<fecha>`.
- Sin prefijo `fixture2030:`: esta instancia es dedicada
  al módulo, así que no hace falta separar namespaces de otras aplicaciones.

---

## 2. Claves, estructuras y TTL

| Clave | Estructura | Operación que la justifica (patrón) | TTL | Dueño de la verdad |
| ----- | ---------- | ----------------------------------- | --- | ------------------ |
| `sesion:<idSesion>`<br>ej. `sesion:SES-0001` | Hash | Crear, validar, renovar y cerrar sesión (§2.1) | 1800 s, renovado | **Redis** |
| `cache:partido:<partido_id>`<br>ej. `cache:partido:P-001` | String (JSON) | Leer ficha / invalidar por gol (§2.2) | 3600 s | **Neo4j** |
| `cache:feed:<partido_id>:<bloque>`<br>ej. `cache:feed:ARG-ESP-20300624:20300624T2000` | String (JSON) | Leer feed / invalidar por moderación (§2.3) | 5 s (ventana actual) · 300 s (ventana cerrada) | **Cassandra** |
| `cache:plantel:<equipo_id>`<br>ej. `cache:plantel:ARG` | String (JSON) | Leer plantel / invalidar por alta o baja (§2.4) | 3600 s | **MongoDB** |
| `partido:<partido_id>:visitas:<fecha>`<br>ej. `partido:P-001:visitas:2030-06-08` | String (entero) | Contar visita (§2.5) | 604800 s (7 días) | **Redis** |

Ninguna clave existe sin operación que la justifique. No hay claves de ranking ni de
conjuntos (ver `patrones_de_acceso.md`, sección 3).

`<bloque>` es el inicio de la ventana de 5 minutos del feed en UTC, formato
`AAAAMMDDTHHMM`. Se escribe sin `:` para no confundirlo con el separador de la clave.

---

## 3. Sesión: campos del Hash

Todos los valores de muestra son **ficticios**. No se guarda token ni contraseña:
la autenticación no forma parte de este módulo.

| Campo | Contenido | Se escribe | Lo modifica la renovación |
| ----- | --------- | ---------- | ------------------------- |
| `usuario_id` | Id de usuario con el formato de Cassandra, ej. `U001` | Al crear | No |
| `nombre_usuario` | Nombre visible (Cassandra lo desnormaliza para evitar lecturas extra) | Al crear | No |
| `rol` | `fan` o `moderador` (Cassandra Q3 habla de moderadores) | Al crear | No |
| `idioma` | `es`, `en`, `pt`, `fr`. Cassandra delega el filtro por idioma del feed a la aplicación; la sesión es de donde la aplicación lo toma | Al crear | No |
| `ultimo_acceso` | Fecha y hora UTC de la última acción, ej. `2030-06-13T20:15:00Z` | Al crear | **Sí** |
| `acciones` | Cantidad de acciones del usuario en la sesión | Al crear (0) | **Sí** (`HINCRBY`) |
| `ubicacion` | Ubicación del cliente al crear la sesión (ficticia) | Al crear | No |
| `dispositivo` | Dispositivo del cliente (ficticio) | Al crear | No |
| `ip_publica` | IP del cliente (ficticia, rango de documentación) | Al crear | No |
| `tipo_conexion` | Tipo de conexión, ej. `wifi`, `móvil` (ficticio) | Al crear | No |

**Estado de acceso:** ningún hito anterior lo define. El grupo lo define como las
características del cliente al establecer la sesión: `ubicacion`, `dispositivo`,
`ip_publica` y `tipo_conexion`. **Solo se registran; no se comparan al validar la
sesión.** Ningún requisito pide compararlos, y comparar
exigiría decidir qué cambio invalida una sesión (por ejemplo, un cambio de red al pasar
de wifi a datos móviles). `ubicacion` queda alineado con la partición geográfica de
usuarios de Hito 3.

**Varias sesiones por usuario:** Hito 3 acepta "dos sesiones activas del mismo usuario
durante un periodo". Por eso la clave lleva el **id de sesión** y no el de usuario
(una clave `sesion:<usuario>` admitiría una sola sesión por usuario).

---

## 4. Contenido de los valores de caché

JSON serializado dentro de un String. Es una **copia simulada** de lo que devolvería la
fuente, no un contrato de otro módulo.

- **Ficha** (`cache:partido:P-001`): una sola clave con la vista completa — `partido_id`,
  `fase`, `grupo`, `fecha`, sede (`id`, `nombre`, `ciudad`), equipo local y visitante con
  sus goles. Campos tomados de `fixture2030-neo4j/import/partidos.csv` y `sedes.csv`.
  El marcador es el conteo de goles por equipo que Neo4j obtiene recorriendo el grafo.
  Se guarda **todo junto** y no en claves separadas por dato: Hito 3 exige consistencia
  causal para Neo4j y una clave por vista se reemplaza o se invalida como unidad, sin
  mostrar un gol en una lista con el marcador viejo.
- **Feed** (`cache:feed:<partido>:<bloque>`): una página de 20 comentarios de la ventana (tamaño de página fijado por este
  módulo) con los campos de Q1 de Cassandra: `comentario_id`, `usuario_id`, `nombre_usuario`,
  `idioma`, `texto`, `estado_moderacion`.
- **Plantel** (`cache:plantel:ARG`): el equipo (`_id`, `nombre`, `confederacion`,
  `grupo`) y sus 26 jugadores (`_id`, `nombre`, `apellido`, `dorsal`, `posicion`) en
  producción. La carga del laboratorio incluye solo una muestra representativa de
  jugadores para comprobar la estructura sin duplicar el dataset de MongoDB.

---

## 5. Identificadores: una limitación conocida

Cada clave usa el ID de **su fuente**. Eso expone una inconsistencia entre módulos
anteriores que este hito **no corrige**:

- Neo4j identifica partidos como `P-001`, `P-002`, … (127 partidos).
- Cassandra identifica el partido con `'ARG-ESP-20300624'` y `'BRA-FRA-20300625'`.
- En el grafo **no existe ningún partido ARG–ESP ni BRA–FRA**: los IDs de Cassandra no
  corresponden a ningún nodo `Partido`.

Consecuencia: la ficha y el contador de un mismo partido usan `P-xxx`, y el feed usa el
ID de Cassandra. El mismo partido, si existiera en ambos, tendría dos nombres en Redis.
Unificarlos exigiría tocar Neo4j o Cassandra, fuera del alcance de este módulo. Los IDs
de equipo y jugador sí coinciden entre MongoDB y Neo4j (`ARG`, `ARG-10`) y se usan tal
cual en el plantel.

---

## 6. TTL: valor, cota de vejez y motivo

El TTL de una copia responde a: *si la invalidación falla o no ocurre, ¿cuánto tiempo
puede verse un dato viejo?* No reemplaza la invalidación (el TTL es un límite máximo de vida, no una decisión de consistencia).

| Dato | TTL | Cota de vejez aceptada | Motivo |
| ---- | --- | ---------------------- | ------ |
| Sesión | 1800 s (30 min) de inactividad | Hasta 30 min sin actividad antes de vencer | Decisión del grupo: 30 min porque acota la memoria con 2–3 M de sesiones (Hito 3: la memoria es el segundo cuello de botella). **Costo aceptado:** quien solo mira sin interactuar (el refresco del feed no renueva) debe autenticarse de nuevo; Hito 3 acepta que "sus usuarios vuelven a autenticarse". |
| Ficha | 3600 s | 1 h **solo si falla la invalidación**; con `DEL` por gol, la copia es siempre reciente | La corrección la da el `DEL` posterior a cada gol; el TTL largo permite que la ficha sobreviva más que las sesiones y el feed bajo presión de memoria (`memoria_y_escalabilidad.md`). **Riesgo asumido:** si un `DEL` se pierde, un marcador viejo puede mostrarse hasta 1 h. Es una decisión del grupo; un TTL de segundos reduciría ese riesgo pero sacrificaría la ficha antes que las sesiones. |
| Feed, ventana actual | 5 s | 5 s | La ventana recibe comentarios todo el tiempo y no se invalida por cada uno. Con 5 s, cada cliente ve a lo sumo 5 s de atraso: Hito 3 acepta que un usuario no vea el último comentario. Es el TTL más corto del módulo: es lo primero que se sacrifica. |
| Feed, ventana cerrada | 300 s | 300 s | Ya no recibe comentarios; solo cambia por moderación, que hace `DEL`. 300 s coincide con el largo de una ventana. |
| Plantel | 3600 s | 1 h solo si falla la invalidación | Cambia de forma esporádica (Hito 3). Las altas y bajas hacen `DEL`. |
| Contador de visitas | 604800 s (7 días) | No aplica: es dato propio | Una clave por día. Se conserva unos días para consultarla y luego vence sola; no crece sin límite. `INCR` no elimina ni renueva el TTL existente; una clave nueva creada por `INCR` se verifica en el laboratorio. El vencimiento se fija con `EXPIRE` dentro de `MULTI/EXEC` junto con cada `INCR`, así no hay un instante en que exista sin TTL. Cada visita renueva los 7 días. Su pérdida no afecta el negocio. |

Los TTL del feed y de la sesión tienen un papel doble: acotan la vejez y definen el orden
en que `volatile-ttl` descarta claves (`memoria_y_escalabilidad.md`).
