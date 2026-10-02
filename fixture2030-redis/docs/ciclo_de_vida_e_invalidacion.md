# Ciclo de vida e invalidación — Caché de usuarios y sesiones (Hito 7)

## Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II

Todo dato temporal de este módulo tiene una decisión explícita de expiración,
renovación, invalidación o conservación. Claves y TTL: `modelo_clave_valor.md`.

---

## 1. Sesión

### 1.1 Etapas

| Etapa | Qué ocurre | Comando(s) |
| ----- | ---------- | ---------- |
| **Crear** | Al autenticar, la aplicación escribe todos los campos y define el vencimiento | `MULTI` · `HSET sesion:<id> …` · `EXPIRE sesion:<id> 1800` · `EXEC` (sin instante en que la sesión exista sin TTL) |
| **Validar** | Se lee la sesión; si existe, es válida | `HGETALL sesion:<id>` |
| **Renovar** | Tras validar que la sesión existe, una acción del usuario actualiza `ultimo_acceso`, suma 1 a `acciones` y reinicia el TTL, sin que otra petición se intercale | `MULTI` · `HSET … ultimo_acceso` · `HINCRBY … acciones 1` · `EXPIRE … 1800` · `EXEC` |
| **Vencer** | Tras 1800 s sin renovación, Redis elimina la clave solo | (nativo) |
| **Cerrar** | El usuario sale: se elimina la clave | `DEL sesion:<id>` |

### 1.2 Reglas

- **Regla de validez:** una sesión es válida si y solo si la clave existe. No hay un
  proceso que recorra las sesiones buscando vencidas: lo hace el TTL.
- **Qué renueva:** solo las **acciones del usuario** (abrir un partido, abrir un plantel,
  comentar). El refresco automático del feed **no** renueva: hacerlo implicaría una
  escritura por cada lectura con millones de sesiones. Costo aceptado: quien solo mira
  sin interactuar vence a los 30 min y se reautentica.
- **Qué no cambia la renovación:** los campos de estado de acceso (`ubicacion`,
  `dispositivo`, `ip_publica`, `tipo_conexion`) se escriben al crear.
- **Por qué `MULTI/EXEC`:** Actualizar un campo de un Hash no extiende su vida por sí solo: `HSET` no toca el TTL; para `HINCRBY` se verifica en el laboratorio. `EXPIRE` lo reinicia. Las tres operaciones
  se ejecutan consecutivas, sin que otro cliente introduzca comandos en el medio. Redis no ofrece `rollback` general: el flujo se diseña de modo que cada comando sea
  válido por sí mismo.
- **Comprobar que venció o fue eliminado:** `TTL sesion:<id>` devuelve `-2` si la clave
  ya no existe. `-1` significaría que existe sin vencimiento, un error de diseño
  para una sesión.
- **Sesión inexistente ≠ error del sistema.** Ante `HGETALL` vacío o `TTL` igual a `-2`,
  la aplicación **pide autenticarse de nuevo** (Hito 3: "sus usuarios vuelven a
  autenticarse"). Esto cubre vencimiento, cierre y pérdida de la sesión.
- **Varias sesiones por usuario:** pueden coexistir (Hito 3). Cada una tiene su clave y su
  propio TTL; cerrar una no cierra las otras.
- **Si Redis cae o se reinicia sin datos:** las sesiones se pierden y los usuarios se
  reautentican (Hito 3). Redis es el dueño de este dato, así que no hay fuente donde
  reconstruirlo; el costo es aceptable por la corta vida de la sesión.

**Renovar una sesión vencida:** `HSET` y `HINCRBY` sobre una clave inexistente la crearían
con solo `ultimo_acceso` y `acciones`, que pasaría la regla de validez. Por eso la
aplicación **valida (`HGETALL`) antes de renovar** y solo renueva si la sesión existe;
reautentica si no. Queda una carrera mínima si vence entre la validación y la renovación.
Qué ocurre exactamente al renovar una sesión **ya vencida** se verifica en el
laboratorio (`scripts/sesiones.redis`) y se registra lo observado en la evidencia, no
se afirma aquí.

---

## 2. Caché: patrón Cache-Aside

Redis queda al margen de la fuente de verdad: la aplicación decide cuándo leer, cargar
e invalidar. Redis no sabe qué cambió en otro módulo.

**Lectura:**

```
clave = "cache:partido:" + partido_id
valor = GET clave
SI valor existe  → responder valor                          (hit)
SINO             → valor = leer de la fuente de verdad
                   SET clave valor EX <ttl>                 (miss y carga)
                   responder valor
```

**Escritura e invalidación:**

```
1. actualizar la fuente de verdad
2. DEL clave
```

**El orden importa:** primero la fuente, después `DEL` (`actualizar_base_de_verdad` y luego `DEL`). Con el orden inverso, un lector podría recargar la copia vieja entre el
`DEL` y la actualización, y dejarla en Redis. Este módulo no mitiga esa carrera; solo fija el orden correcto.

**Al guardar la copia siempre con `EX`** (opción de vencimiento de `SET`; alternativa: `SETEX`): `SET` sin opciones **elimina** el TTL anterior. Una copia sin TTL quedaría sin cota de vejez.

---

## 3. Caché por dato

### 3.1 Ficha del partido

| Aspecto | Decisión |
| ------- | -------- |
| Fuente de verdad | Neo4j (marcador derivado de los eventos `Gol`) |
| Condición de hit | `GET cache:partido:<id>` devuelve valor |
| Camino del miss | Consultar Neo4j, `SET … EX 3600`, responder |
| Invalida | Un evento `Gol` (o un cambio que altere la ficha) → actualizar Neo4j y luego `DEL` |
| Permanencia máxima | 3600 s; con invalidación correcta la copia refleja el último gol |
| Si Redis no tiene la clave o no está disponible | Se lee directo de Neo4j. Hito 3 lo declara el primer cuello de botella: perder esta caché es el riesgo más caro del módulo |

**Por qué el TTL solo no alcanza:** el marcador cambia con cada gol y el espectador
espera verlo. Con TTL de 1 h y sin `DEL`, un gol tardaría hasta 1 h en aparecer. La
frescura la da la invalidación; el TTL es el seguro si esa invalidación falla.

**Una clave por vista consistente:** la ficha completa está en una sola clave (Hito 3:
consistencia causal). Al invalidarla se descarta como unidad.

### 3.2 Feed de comentarios

| Aspecto | Decisión |
| ------- | -------- |
| Fuente de verdad | Cassandra (`comentarios_feed`, consulta Q1) |
| Condición de hit | `GET cache:feed:<partido>:<bloque>` devuelve valor |
| Camino del miss | Ejecutar Q1 (página de 20 comentarios, tamaño fijado por este módulo), `SET … EX 5` o `EX 300`, responder |
| Invalida | **Solo la moderación**: cuando un moderador oculta un comentario, se actualiza `estado_moderacion` en Cassandra y luego `DEL` de esa ventana |
| Permanencia máxima | 5 s (ventana actual) · 300 s (ventana cerrada) |
| Si Redis no tiene la clave o no está disponible | Se lee directo de Cassandra, que escala horizontalmente (Hito 3); costo bajo |

**Por qué aquí el TTL sí alcanza:** la ventana actual recibe comentarios de forma
continua (111–555 por segundo, ráfagas del orden de 10.000 por segundo, doc de Cassandra
§1.1). Invalidar por cada comentario anularía la caché. Hito 3 acepta que un usuario no
vea el último comentario durante unos segundos, y 5 s es esa cota.

**Por qué igual hay `DEL`:** un comentario oculto por moderación no puede seguir visible
hasta que venza el TTL. Es el cambio de negocio que exige frescura. Si la
ventana ya cerró, además, el TTL de 300 s es la cota de seguridad.

**Qué no se hace:** mantener una lista en Redis con los comentarios más recientes
escritos por la ingesta. Convertiría a Redis en un segundo destino de escritura del
pipeline de comentarios, y para estos casos alcanza con Cache-Aside.

### 3.3 Plantel del equipo

| Aspecto | Decisión |
| ------- | -------- |
| Fuente de verdad | MongoDB (`equipos` y `jugadores`) |
| Condición de hit | `GET cache:plantel:<equipo>` devuelve valor |
| Camino del miss | Leer el equipo y sus 26 jugadores de MongoDB (dos lecturas), `SET … EX 3600`, responder |
| Invalida | Alta o baja de un jugador, o cambio del equipo → actualizar MongoDB y luego `DEL` |
| Permanencia máxima | 3600 s |
| Si Redis no tiene la clave o no está disponible | Se lee directo de MongoDB, que atiende lecturas por `_id` y tiene réplicas (Hito 3) |

### 3.4 Contador de visitas

| Aspecto | Decisión |
| ------- | -------- |
| Fuente de verdad | Redis (no hay otra) |
| Creación | `MULTI` · `INCR …` · `EXPIRE … 604800` · `EXEC`: la clave nunca queda sin TTL |
| Actualización | `INCR` dentro del `MULTI/EXEC` anterior |
| Conservación | Vence a los 7 días |
| Si Redis cae | Se pierde el contador del día; no afecta datos de negocio |

---

## 4. Tabla de coherencia por clave

| Clave | Verdad | Invalida | TTL | Si Redis cae |
| ----- | ------ | -------- | --- | ------------ |
| `sesion:<id>` | Redis | `DEL` al cerrar; vence por inactividad | 1800 s, renovado por acciones | Se pierde; el usuario se reautentica (Hito 3) |
| `cache:partido:<id>` | Neo4j | `DEL` tras actualizar Neo4j (gol) | 3600 s | Lectura directa a Neo4j (primer cuello de botella, Hito 3) |
| `cache:feed:<partido>:<bloque>` | Cassandra | `DEL` solo por moderación; **no** por comentario nuevo | 5 s actual · 300 s cerrada | Lectura directa a Cassandra |
| `cache:plantel:<equipo>` | MongoDB | `DEL` tras alta o baja de plantel | 3600 s | Lectura directa a MongoDB |
| `partido:<id>:visitas:<fecha>` | Redis | — | 604800 s | Se pierde el contador |

---

## 5. Límites de este módulo

- **Varios clientes ante una clave vencida:** si muchos clientes consultan a la vez una
  clave que acaba de vencer o fue invalidada, cada uno puede ir a la fuente antes de que
  alguno guarde la copia. El módulo no mitiga este caso y no se mide en este hito.
- **La fuente es simulada** (no se integra físicamente con los otros módulos). Los scripts reemplazan la lectura de Neo4j, Cassandra y MongoDB por datos
  de muestra y representan el cambio de la fuente con una escritura sobre el valor
  simulado.
- **Sin sincronización automática:** nadie avisa a Redis que cambió la fuente. La
  invalidación es parte del flujo de la aplicación.
