# Patrones de acceso — Caché de usuarios y sesiones (Hito 7)

## Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II

Redis no es fuente de verdad de ningún dato del negocio. Guarda estado temporal propio
(sesiones, contador de visitas) y copias descartables de datos que viven en otros
módulos: la ficha de un partido (Neo4j, Hito 5), el feed de comentarios (Cassandra,
Hito 6) y el plantel de un equipo (MongoDB, Hito 4).

---

## 1. Problema de concurrencia

Los números siguientes son **supuestos de diseño tomados de Hitos 1 y 3 y de los docs de
Cassandra**; no son mediciones de este módulo.

- **Usuarios y sesiones:** entre 2 y 3 millones de sesiones simultáneas, de corta
  duración, accedidas por clave (Hito 3).
- **Solicitudes:** más de 100.000 por segundo en situaciones de alta demanda (Hito 2, Hito 3).
- **Lecturas repetidas:** en un partido de alta audiencia, muchos clientes piden a la vez
  la misma ficha, el mismo plantel y la misma ventana del feed. El feed se refresca por
  consulta periódica de los clientes: Cassandra la describe como "la consulta más
  caliente del sistema" (`fixture2030-cassandra/docs/patrones_de_acceso.md`, Q1).
- **Ráfagas:** un gol multiplica entre 10 y 20 veces la tasa de comentarios (doc de
  Cassandra, §1.1), y cambia la ficha del partido.
- **Actualizaciones:** la ficha cambia solo con eventos del partido; el plantel cambia
  de forma esporádica (Hito 3: "las altas y bajas de plantel son esporádicas"); la
  ventana actual del feed cambia constantemente.
- **Cuello de botella que Redis alivia:** Hito 3 declara a Neo4j como el primer cuello de
  botella del sistema y a la memoria de Redis como el segundo. Las lecturas repetidas de
  la ficha son la carga que más conviene no repetir contra Neo4j.

Las operaciones de escritura concurrentes de este módulo son el contador de visitas de un
partido (`INCR`) y el contador de acciones de la sesión dentro de la renovación
(`HINCRBY` en `MULTI/EXEC`).

---

## 2. Patrones de acceso

Frecuencias **cualitativas** (muy alta, alta, baja) derivadas de las fuentes de la
sección 1. No hay cifras propias hasta que la evidencia las produzca con método.
Resumen por tipo de operación (lectura / escritura / actualización):

| Dato | Lectura | Escritura | Actualización |
| ---- | ------- | --------- | ------------- |
| Sesión | Muy alta (validar) | Alta (crear) | Alta (renovar por acción del usuario) |
| Ficha | Muy alta | Una por miss (carga de la copia) | Baja (un gol en la fuente) |
| Feed | Muy alta | Una por miss | La fuente cambia sin parar; la copia se invalida solo por moderación (baja) |
| Plantel | Alta | Una por miss | Muy baja (altas y bajas) |
| Visitas | Baja (consulta) | Muy alta en la final (`INCR`) | Es la misma operación que la escritura |

### 2.1 Sesión de usuario

Estado temporal propio: **Redis es el dueño** del dato (Hito 2: datos efímeros de corta vida,
accedidos por clave). No existe fuente externa.

| Patrón | Quién | Entrada | Respuesta | Frecuencia | Temporal / fuente | Estructura y motivo |
| ------ | ----- | ------- | --------- | ---------- | ----------------- | ------------------- |
| **Crear sesión** | Aplicación, al autenticar al usuario | Id de sesión nuevo + datos del usuario y del cliente | Confirmación; la sesión existe con su vencimiento | Alta (una por ingreso; picos al empezar un partido) | Todo temporal; sin fuente externa | **Hash**: la sesión es un registro de campos que se leen y modifican por separado. `HSET` + `EXPIRE` dentro de `MULTI/EXEC` |
| **Validar sesión** | Aplicación, en cada petición que lo requiere | Id de sesión | Los campos de la sesión, o "no existe" | Muy alta (acceso puntual por clave, Hito 3) | Temporal | Hash: `HGETALL` lee todo en una operación; clave ausente = sesión no válida |
| **Renovar sesión** | Aplicación, ante una **acción del usuario** (abrir partido o plantel, comentar). No ante el refresco automático del feed | Id de sesión | Sesión con `ultimo_acceso` nuevo, contador de acciones +1 y vencimiento reiniciado | Alta, menor que validar | Temporal | Hash dentro de `MULTI/EXEC`: `HSET` + `HINCRBY` + `EXPIRE` sin intercalar otra petición; solo si la validación previa encontró la sesión |
| **Cerrar sesión** | Usuario (cierre explícito) | Id de sesión | La sesión deja de existir | Baja | Temporal | `DEL` sobre la clave del Hash |

La inactividad no es un patrón de aplicación: la sesión vence sola por TTL (el servidor elimina la clave; no se necesita que la aplicación consulte miles de sesiones).

### 2.2 Ficha de un partido

Fuente de verdad: **Neo4j**. El marcador no es una propiedad del nodo `Partido`; se
obtiene contando los eventos `Gol` del partido (`Evento -[:OCURRE_EN]-> Partido`) por el
equipo de cada jugador (`modelo_grafo.md` §2: `Partido` solo tiene `fase`, `grupo` y
`fecha`). Es una derivación del grupo, no una pregunta del doc de Neo4j. Se cachea porque
es la lectura que más conviene no repetir contra Neo4j (Hito 3: primer cuello de botella).

| Patrón | Quién | Entrada | Respuesta | Frecuencia | Temporal / fuente | Estructura y motivo |
| ------ | ----- | ------- | --------- | ---------- | ----------------- | ------------------- |
| **Leer ficha** (hit / miss) | Cualquier espectador | Id de partido de Neo4j (ej. `P-001`) | Ficha completa: equipos, fase, fecha, sede y marcador | Muy alta (muchos usuarios piden el mismo partido) | La copia es temporal; la verdad está en Neo4j | **String** con JSON. Una sola clave por vista completa: `GET`, y en miss `SET … EX` |
| **Invalidar ficha por gol** | Quien registra el evento en Neo4j | Id de partido | El próximo `GET` ya no devuelve el marcador anterior | Baja (los goles de un partido) | Copia temporal | `DEL` (Cache-Aside): **primero** se actualiza Neo4j, **después** se hace `DEL` |

### 2.3 Feed de comentarios en vivo

Fuente de verdad: **Cassandra** (`comentarios_feed`).

| Patrón | Quién | Entrada | Respuesta | Frecuencia | Temporal / fuente | Estructura y motivo |
| ------ | ----- | ------- | --------- | ---------- | ----------------- | ------------------- |
| **Leer feed** | Cualquier espectador | Id de partido de Cassandra (ej. `ARG-ESP-20300624`) + bloque temporal de 5 min | Página de 20 comentarios de esa ventana (tamaño de página fijado por este módulo; Cassandra Q1 solo define el cursor de paginación) | Muy alta | Copia temporal; la verdad está en Cassandra | **String** con JSON de la página. Misma ventana pedida por muchos clientes |
| **Invalidar feed por moderación** | Moderador, al ocultar un comentario | Id de partido + bloque del comentario | El próximo `GET` no incluye el comentario oculto | Baja | Copia temporal | `DEL` de la ventana afectada, después de actualizar `estado_moderacion` en Cassandra |

Un comentario nuevo **no** invalida la ventana: se acepta que un usuario no vea el
último comentario durante unos segundos (Hito 3). Ver
`ciclo_de_vida_e_invalidacion.md`.

### 2.4 Plantel de un equipo

Fuente de verdad: **MongoDB** (`equipos` y `jugadores`).

| Patrón | Quién | Entrada | Respuesta | Frecuencia | Temporal / fuente | Estructura y motivo |
| ------ | ----- | ------- | --------- | ---------- | ----------------- | ------------------- |
| **Leer plantel** | Cualquier espectador | Código de equipo de MongoDB (ej. `ARG`) | El equipo y sus 26 jugadores | Alta | Copia temporal; verdad en MongoDB | **String** con JSON: en MongoDB son dos lecturas (equipo y jugadores); la copia las entrega en una |
| **Invalidar plantel por alta/baja** | Quien modifica el plantel en MongoDB | Código de equipo | El próximo `GET` trae el plantel nuevo | Muy baja (Hito 3: esporádicas) | Copia temporal | `DEL`, después de actualizar MongoDB |

La copia se justifica por descarga de carga a 100.000 req/s, no por afirmar que Redis
sea "más rápido" que MongoDB: eso no se afirma sin medirlo.

### 2.5 Contador de visitas

Estado temporal propio: **Redis es el dueño**. Es una métrica de acceso, no un dato del
negocio, y no duplica ningún conteo de Cassandra.

| Patrón | Quién | Entrada | Respuesta | Frecuencia | Temporal / fuente | Estructura y motivo |
| ------ | ----- | ------- | --------- | ---------- | ----------------- | ------------------- |
| **Contar visita** | Aplicación, cada vez que un usuario abre la ficha | Id de partido de Neo4j + fecha del día | Total de visitas del partido ese día | Muy alta en la final (miles de clientes sobre la misma clave) | Temporal, sin fuente externa | **String** + `INCR` y `EXPIRE` en `MULTI/EXEC`: `INCR` es atómico; evita el antipatrón `GET` → sumar → `SET` |

---

## 3. Qué no va a Redis y por qué

| Dato | Dónde vive | Por qué no está en Redis |
| ---- | ---------- | ------------------------ |
| Likes y total de comentarios por partido | Cassandra (`likes_por_comentario`, `contadores_por_partido`, tipo `counter`) | Ya tienen su solución. Moverlos duplicaría la fuente de verdad. |
| Perfil de usuario | Colección `usuarios` de MongoDB (Hito 2, Hito 3) | **No existe en el módulo MongoDB implementado** (solo `equipos` y `jugadores`): no hay fuente contra la cual demostrar hit, miss o invalidación. La sesión guarda solo los campos mínimos que el resto del sistema usa. |
| Goleadores | Neo4j | Son datos del grafo. Un conjunto ordenado paralelo sería una segunda verdad. |
| Ranking de partidos más vistos  | — | Un ranking solo corresponde si los patrones de acceso lo requieren. El equipo **no declara ningún patrón de lista o Top N**: ninguna pregunta de este módulo necesita ordenar partidos. Se justifica por escrito su ausencia en vez de agregar una estructura sin operación que la justifique. |
| Fixture por fase (programación de partidos) | Neo4j (pregunta 5 del modelo) | Fuera de alcance: aporta poco frente a la ficha y no agrega un patrón nuevo. |
| Set de usuarios conectados a un partido | — | El TTL se asocia a la clave completa, no a cada miembro: al vencer una sesión, su miembro quedaría en el conjunto. Contar miembros obligaría a recorrer todo el conjunto. |

Toda decisión de este documento se aplica en `modelo_clave_valor.md`: cada clave remite
al patrón de la sección 2 que la justifica.
