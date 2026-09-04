# Hito 4 — Decisiones Documentales

## Módulo de Equipos y Jugadores del Fixture 2030

Ingeniería de Datos II — Grupo 11

> **Alcance.** Este documento cubre la totalidad de la Estructura del Trabajo
> Esperado para el Hito 4 (ítems 1 a 5): ambiente de ejecución, diseño documental,
> carga de datos idempotente, operaciones y consultas obligatorias, y análisis de
> rendimiento con optimización demostrada mediante `explain()`.

---

## 1. Decisiones heredadas que condicionan este módulo

Este hito no elige tecnología: la recibe. Las decisiones vinculantes son:

**Del Hito 2 (matriz de decisión, Sección 3).** Equipos y Jugadores se persisten
en **MongoDB**, modelo documental. El criterio registrado fue: *"entidades de
estado con atributos variables o semiestructurados; se recupera la entidad
completa por ID en una sola lectura, sin joins"*. Se descartaron Neo4j —volumen
bajo y relaciones simples no justifican un grafo— e IRIS —la herencia y
composición del modelo de objetos no se aprovechan.

**Del Hito 3 (Secciones 1 a 3).** Para Equipos, Jugadores y Alineaciones:

- Volumen bajo, **lectura frecuente y escritura ocasional**, recuperación
  principalmente por ID.
- **No se particiona**: el volumen no supera la capacidad de un único servidor.
- **Sí se replica**, no por volumen sino por disponibilidad: el SLA de 99,99 % y
  la operación multi-región exigen eliminar el punto único de falla.
- Esquema **AP** en el análisis CAP, con **consistencia eventual** aceptada
  explícitamente: *"son entidades en las que no escribiremos a menudo, pero que
  tienen que estar disponibles para la lectura constantemente"*.

**Del Hito 1 (tabla de volúmenes).** Equipos: 64, crecimiento *"ninguno
(fijo)"*. Jugadores: 1.500+, crecimiento *"ninguno (fijo)"*.

### 1.1. Observación sobre una inconsistencia del Hito 2

La fila de MongoDB en la matriz del Hito 2 (Sección 3) incluye *Partidos* entre
las entidades asignadas al modelo documental, mientras que la Sección 4 y el mapa
de persistencia de la Sección 5 del **mismo documento** los asignan a Neo4j, y el
Hito 3 los trata consistentemente como grafo. Se registra acá para que quede
constancia: **la versión vigente es la del Hito 3** (Partidos y Eventos en
Neo4j). Este módulo no persiste partidos, de modo que la inconsistencia no afecta
a la implementación, pero sí a los argumentos que la citan (ver §3.1).

---

## 2. Diseño de las colecciones

Dos colecciones en la base `fixture2030`.

### 2.1. Colección `equipos`

```javascript
{
  _id: "ARG",                          // código FIFA — identificador natural
  nombre: "Argentina",
  confederacion: "CONMEBOL",           // UEFA | CONMEBOL | CAF | AFC | CONCACAF | OFC
  grupo: "J",                          // A a P — 16 grupos de 4
  ranking_fifa: 1,                     // int, 1-250
  participaciones_mundiales: 18,       // int, 0-30
  director_tecnico: "Lionel Scaloni",
  anfitrion: true                      // las seis sedes del Mundial 2030
}
```

Campos obligatorios: `_id`, `nombre`, `confederacion`, `grupo`, `ranking_fifa`,
`participaciones_mundiales`, `anfitrion`.

### 2.2. Colección `jugadores`

```javascript
{
  _id: "ARG-10",                       // <código FIFA>-<dorsal>
  nombre: "Nahuel",
  apellido: "Bustos",
  dorsal: 10,                          // int, 1-99, único dentro del plantel
  posicion: "Mediocampista",           // Arquero | Defensor | Mediocampista | Delantero
  pie_habil: "Derecho",                // Derecho | Izquierdo | Ambidiestro
  fecha_nacimiento: ISODate("2007-07-07T00:00:00Z"),
  altura_cm: 186,                      // int, 150-215
  peso_kg: 70,                         // int, 50-120
  club: "Benfica",
  capitan: true,                       // exactamente uno por plantel

  equipo: {                            // referencia + desnormalización parcial
    _id: "ARG",                        // → equipos._id
    nombre: "Argentina",               // copia de solo lectura
    confederacion: "CONMEBOL"          // copia de solo lectura
  }
}
```

Campos obligatorios: `_id`, `nombre`, `apellido`, `dorsal`, `posicion`,
`fecha_nacimiento`, `equipo` (con sus tres subcampos).

`fecha_nacimiento` se almacena como `Date` y no como cadena, para que las
consultas por rango de edad y las agregaciones del ítem 4 puedan resolverse en el
motor y no en la aplicación.

---

## 3. Documentación de diseño

| Decisión | Alternativas consideradas | Elección | Justificación | Impacto esperado |
|---|---|---|---|---|
| **Relación equipo–jugador** | (a) Embeber el plantel completo dentro del documento de equipo. (b) Referencias puras: `jugadores.equipo_id` sin copiar nada. (c) Referencias + desnormalización parcial del equipo dentro del jugador. (d) Embedding bidireccional. | **(c) Referencias + desnormalización parcial** (*extended reference*) | El jugador debe seguir siendo una entidad recuperable por ID desde **fuera de MongoDB**: el Hito 3 modela los eventos en Neo4j con relaciones `ANOTA`, `ASISTE`, `REEMPLAZA` y `PARTICIPA` que apuntan a jugadores, y las alineaciones los referencian individualmente. Embebido en un array, el jugador deja de tener identidad de primera clase. La copia de `nombre` y `confederación` del equipo evita el `$lookup` en la consulta dominante —listar jugadores mostrando su selección— y su costo (quedar desfasada) es exactamente la consistencia eventual que el Hito 3 ya declaró aceptable para este subsistema. | Perfil de jugador y plantel completo se resuelven ambos en una sola lectura indexada. Se acepta redundancia acotada y la obligación de propagar los cambios de nombre de equipo, con un control de desincronización en la verificación de integridad. |
| **Validación documental** | (a) Sin validación en la base, confiando en el script de carga. (b) `$jsonSchema` con `validationAction: "warn"`. (c) `$jsonSchema` con `validationAction: "error"` y `additionalProperties: false`. | **(c) `$jsonSchema` estricto, con rechazo** | RNF3 pide que **no existan** campos críticos ausentes ni identificadores duplicados. Una advertencia registra el problema pero lo deja entrar; una regla en el script de carga solo protege a ese script, y el módulo se escribirá también desde las operaciones del ítem 4. El motor es el único punto que ningún cliente puede saltear. `additionalProperties: false` cierra el documento: esquema flexible no significa ausencia de diseño, y un atributo no previsto es casi siempre un error de tipeo. | Toda escritura inválida falla en el momento de escribir, con código 121. Costo: cada evolución del esquema exige un `collMod` — por eso el script de setup lo aplica de forma idempotente en lugar de crear la colección. |
| **Estrategia de identificadores** | (a) `ObjectId` autogenerado. (b) UUID. (c) Identificador de negocio: código FIFA para equipos, `<código FIFA>-<dorsal>` para jugadores. | **(c) Identificador de negocio** | Es lo que hace posible la carga idempotente: el `upsert` necesita una clave derivada del dato, estable entre corridas. Con `ObjectId` cada ejecución generaría documentos nuevos, o exigiría un índice único adicional sobre el campo de negocio y hacer el `upsert` por ese campo —el `_id` quedaría como identificador redundante. Además `_id` ya está indexado de forma única por MongoDB: la unicidad del código FIFA sale sin costo, cubriendo la mitad de RNF3. Y el identificador es legible, lo que importa cuando lo referencian otros subsistemas de la arquitectura políglota. | Recuperación por identificador sin índice adicional. Evidencia y referencias cruzadas legibles. Costo: `_id` es inmutable en MongoDB, así que un cambio de dorsal o de selección obliga a recrear el documento (ver §6.2). |
| **Índices principales** | Indexar solo lo medido, frente a indexar preventivamente todo campo consultable (confederación del jugador, club, ranking global, fecha de nacimiento). | **Seis índices**: tres por colección, cada uno atado a una consulta concreta o a una restricción de integridad. Los candidatos sin evidencia quedan fuera. | La consigna es explícita: *"un índice no es una mejora automática"*. Cada índice cuesta almacenamiento y trabajo en cada escritura. Dos de los seis existen por integridad y no por rendimiento (`nombre` único en equipos, `(equipo._id, dorsal)` único en jugadores) y hacen cumplir RNF3 en el motor; los otros cuatro responden a las consultas de mayor frecuencia previstas. `_id` no necesita índice adicional: ya lo tiene. | Las consultas por plantel, por grupo y por confederación filtran y ordenan con el mismo índice, sin ordenamiento en memoria. Los índices candidatos descartados se reevaluarán en el ítem 5 con evidencia de `explain()`. |
| **Carga y actualización** | (a) `/docker-entrypoint-initdb.d`. (b) `mongoimport` de un dump. (c) `deleteMany` + `insertMany`. (d) `bulkWrite` con `updateOne` + `upsert`, invocado explícitamente. | **(d) `bulkWrite` con `upsert`**, sobre datos generados de forma determinista | RF8 pide que **volver a ejecutar** el procedimiento no genere duplicados ni inconsistencias. (a) queda descartada de raíz: `initdb.d` se ejecuta una única vez, cuando el volumen está vacío, así que la segunda corrida nunca ocurre y no hay nada que demostrar. (c) tampoco es idempotencia sino recarga destructiva: borra los cambios que las operaciones del ítem 4 hayan hecho y no puede distinguir "no había nada que cambiar" de "reescribí todo". Con `upsert` la operación converge al mismo estado sin destruir nada, y el resultado lo dice: `matched 1664, upserted 0, modified 0`. | La segunda corrida y las sucesivas reportan cero inserciones y cero modificaciones. Esa salida es la evidencia directa de RF8. Requiere que los datos sean deterministas: si el generador produjera personas distintas en cada corrida, el `upsert` modificaría los 1.664 documentos en lugar de no hacer nada. |

### 3.1. La decisión de embedding, en detalle

Es la decisión central del hito y merece que se expongan también los argumentos
que **no** la sostienen.

**Argumentos que suelen invocarse y que acá no aplican:**

- *El límite de 16 MB por documento.* No es un factor. Un plantel de 26 jugadores
  ocupa alrededor de 7 KB. Embeber cabría holgadamente.
- *La contención de escritura sobre el documento de equipo.* Tampoco. El Hito 1
  clasifica a ambas entidades con crecimiento *"ninguno (fijo)"* y el Hito 3 las
  describe como de *"escritura ocasional"*. No hay escrituras concurrentes que
  compitan por el mismo documento.
- *Los arrays sin cota.* El plantel tiene un techo reglamentario de 26. No es un
  array que crece sin límite.

Descartados esos, el argumento decisivo es uno solo:

**El jugador tiene que ser referenciable desde fuera de esta base de datos.** La
arquitectura del Hito 3 es políglota, y los jugadores no viven solo acá. Los
eventos del partido se persisten en Neo4j con relaciones `ANOTA`, `ASISTE`,
`REEMPLAZA` y `PARTICIPA` cuyo destino es un jugador; las alineaciones —entre
5.000 y 6.000 registros según el Hito 1— vinculan jugadores con partidos. Todos
esos vínculos necesitan un identificador de jugador estable, único a nivel del
sistema entero y resoluble con una lectura directa.

Un subdocumento dentro de un array no cumple eso. Su dirección sería el par
(documento de equipo, posición en el array), que cambia si el array se reordena;
y aunque se le agregara un identificador sintético, MongoDB no puede imponer un
índice único sobre ese campo a nivel de colección ni recuperarlo con una lectura
por `_id` — habría que consultar por el array y proyectar con `$elemMatch`. El
criterio del Hito 2 para elegir MongoDB fue precisamente *"se recupera la entidad
completa por ID en una sola lectura"*, y el jugador **es** una entidad que se
recupera así: el perfil de jugador es un caso de uso propio, no un fragmento del
equipo.

**Por qué entonces desnormalizar en parte.** Con referencias puras, mostrar un
listado de jugadores con su selección exige un `$lookup` o una segunda consulta.
Copiar `nombre` y `confederación` dentro del jugador lo resuelve en una lectura.
El costo es que esas copias pueden quedar desfasadas respecto del documento de
equipo. Se acepta por dos razones: el nombre y la confederación de una selección
son de los datos más estables del modelo —el Hito 1 los clasifica como fijos—, y
el Hito 3 ya declaró para este subsistema un esquema AP con consistencia
eventual, es decir, que una lectura temporalmente desactualizada es tolerable
acá. El riesgo no se deja sin control: la verificación de integridad incluye una
comprobación específica de desincronización entre el snapshot y su fuente.

**Lo que se pierde.** Recuperar un equipo *con* su plantel completo pasa a
requerir dos lecturas, o un `$lookup`. Es un costo real y consciente: se prefiere
pagarlo en esa consulta antes que romper la identidad del jugador, que es lo que
el resto de la arquitectura necesita.

---

## 4. Índices

| Colección | Índice | Tipo | Consulta o regla que lo justifica |
|---|---|---|---|
| `equipos` | `{ nombre: 1 }` | Único | **Integridad (RNF3).** Impide dos selecciones con el mismo nombre. Sirve además la búsqueda por nombre exacto. |
| `equipos` | `{ confederacion: 1, ranking_fifa: 1 }` | Compuesto | Listado de los equipos de una confederación ordenado por ranking. Filtra y ordena con el mismo índice, sin `SORT` en memoria. |
| `equipos` | `{ grupo: 1 }` | Simple | Recuperación de los 4 integrantes de un grupo — la vista base del fixture. |
| `jugadores` | `{ "equipo._id": 1, dorsal: 1 }` | Único, compuesto | **Integridad (RNF3).** El dorsal es único dentro de un plantel, no globalmente. Su prefijo `equipo._id` sirve además la consulta más frecuente del módulo: el plantel completo de una selección. |
| `jugadores` | `{ "equipo._id": 1, posicion: 1 }` | Compuesto | Plantel filtrado por puesto (los arqueros de una selección), que es la consulta que alimenta la carga de una alineación. |
| `jugadores` | `{ apellido: 1, nombre: 1 }` | Compuesto | Búsqueda de un jugador por nombre desde la interfaz de consulta, con orden alfabético resuelto por el índice. |

**Índices deliberadamente no creados:** `equipo.confederacion`, `club`,
`ranking_fifa` global, `fecha_nacimiento`. Son campos consultables, pero ninguna
consulta medida los exige todavía. Se reevaluarán en el ítem 5 con evidencia de
`explain()`. Crear un índice "por las dudas" contradice el criterio explícito de
la consigna y agrega costo de escritura sin contrapartida demostrada.

Nótese que `{ "equipo._id": 1, dorsal: 1 }` y `{ "equipo._id": 1, posicion: 1 }`
comparten prefijo. La redundancia es intencional: el primero existe por
integridad y no podría reemplazarse por el segundo sin perder la unicidad; el
segundo existe por rendimiento y no podría reemplazarse por el primero, porque
`dorsal` no filtra por posición.

---

## 5. Revisión justificada del Hito 3: la notación N/R/W

El Hito 3 (Sección 3) expresó la replicación de este subsistema así:

> *"La replicación es master-slave, con el primario recibiendo las escrituras y
> los secundarios sirviendo las lecturas, bajo un quórum N=3, R=1, W=2, donde
> R+W = 3 ≤ N y la garantía es eventual."*

**Se retira esa notación para MongoDB.** El modelo N/R/W proviene de Dynamo y
describe replicación **sin líder**: cualquier réplica acepta escrituras, W es
cuántas confirman, R es a cuántas se consulta al leer, y `R + W > N` garantiza
que el conjunto leído y el escrito se solapen en al menos una réplica —lo que
permite reconciliar versiones divergentes. La aritmética solo tiene sentido si
las réplicas pueden divergir.

MongoDB usa replicación **con líder**. En un conjunto de réplicas hay un único
primario y todas las escrituras pasan por él; los secundarios copian el oplog y
nunca aceptan escrituras propias, de modo que no pueden divergir y no hay nada
que reconciliar. Concretamente:

- **W** tiene un análogo aproximado: `writeConcern`, que sí expresa cuántos
  miembros deben confirmar.
- **R no existe.** Una lectura va a **exactamente un** miembro, determinado por
  `readPreference`. MongoDB nunca consulta varias réplicas para compararlas.
  "R=1" no es una elección de configuración: es lo único que el motor hace, y
  "R=2" es inexpresable.
- **`R + W > N` no significa nada.** El Hito 3 llegaba a la conclusión correcta
  —garantía eventual— por un camino que no se sostiene. Es eventual porque el
  secundario aplica el oplog de forma asíncrona, no porque `1 + 2 ≤ 3`. Con el
  mismo W y el mismo N, leer del primario daría garantía fuerte y la fórmula
  seguiría dando `3 ≤ 3`. En MongoDB la consistencia la determina **dónde se
  lee**, no a cuántos.

**Formulación que la reemplaza, sin cambiar la decisión de fondo:**

> Conjunto de réplicas de tres miembros con primario único. Las escrituras
> —altas y bajas de plantel, esporádicas— se confirman con
> `writeConcern: "majority"`, lo que las vuelve resistentes a un failover sin
> competir con el tráfico de lectura, dado que son poco frecuentes. Las lecturas,
> que son el patrón dominante, se dirigen a secundarios con
> `readPreference: "secondaryPreferred"` para escalar capacidad de lectura,
> aceptando que un secundario puede ir algunos milisegundos atrasado. Esa demora
> acotada **es** la consistencia eventual que el análisis CAP del Hito 3 declaró
> aceptable para este subsistema. La mayoría del conjunto interviene únicamente
> en la elección de un nuevo primario: tres miembros toleran la pérdida de uno.
> No se particiona, por las razones ya establecidas en el Hito 3.

La decisión de arquitectura no cambia —tres miembros, lecturas sobre
secundarios, garantía eventual, sin particionamiento—; cambia el vocabulario, que
ahora describe el motor que efectivamente se usa. La notación N/R/W se mantiene
donde sí es aplicable: **Cassandra**, donde el nivel de consistencia es una
perilla real y configurable por consulta.

**Nota sobre el ambiente local.** El `docker-compose.yaml` de esta entrega levanta
un único `mongod`, no el conjunto de tres miembros. Ningún requisito funcional del
Hito 4 pide replicación —RF1 pide un entorno local reproducible y RF2 persistencia—
y montarla agregaría tres contenedores con dependencia de orden de arranque, en
contra de RNF1 y RNF7, sin aportar evidencia de nada que este hito evalúe.

---

## 6. Limitaciones detectadas

### 6.1. MongoDB no tiene integridad referencial declarativa

`$jsonSchema` valida cada documento por separado. No puede comprobar que
`jugadores.equipo._id` apunte a un equipo existente: no hay claves foráneas. Un
jugador huérfano es un documento perfectamente válido para el validador.

Se compensa en dos frentes. **Prevención:** el script de carga genera los
jugadores a partir de los equipos *ya persistidos en la base*, no del archivo de
datos, de modo que es imposible producir un jugador cuyo equipo no exista — la
relación queda garantizada por construcción. **Detección:**
`04-verificar-integridad.js` cuenta los jugadores con referencia rota y falla si
hay alguno.

### 6.2. El `_id` de jugador acopla identidad a equipo y dorsal

`ARG-10` codifica la selección y el dorsal. Como `_id` es inmutable en MongoDB,
un jugador que cambia de dorsal o es convocado por otra selección no puede
actualizarse: hay que borrar el documento y crear uno nuevo, y actualizar toda
referencia externa —incluidas las de Neo4j.

Se acepta porque el Hito 1 clasifica el volumen de jugadores como fijo, sin
crecimiento, y los planteles se cierran antes del inicio del torneo: el escenario
de cambio de dorsal a mitad de competencia no se da. La alternativa —un
identificador de persona independiente del dorsal y del equipo— es más robusta
frente a un modelo con histórico de convocatorias entre torneos, y sería la
elección correcta si el alcance se ampliara en esa dirección. Queda registrada
como decisión a reevaluar.

### 6.3. El snapshot desnormalizado puede desfasarse

Es el costo aceptado de la decisión de §3.1. Si una selección se renombrara sin
propagar el cambio a sus jugadores, las lecturas sin `$lookup` devolverían el
nombre viejo. La verificación de integridad incluye un control específico que
compara cada snapshot contra su documento fuente. La operación de actualización
propagada corresponde al ítem 4.

### 6.4. El ambiente local no reproduce la topología productiva

Un solo nodo, sin autenticación. Justificado en §5 y detallado en el README.

### 6.5. Los datos de jugadores son sintéticos

RNF8 lo habilita explícitamente. Los equipos, confederaciones, rankings y
directores técnicos corresponden a datos reales o verosímiles; los nombres,
clubes y datos físicos de los jugadores son generados. La clasificación al
Mundial 2030 aún no ocurrió, de modo que los 64 participantes son una hipótesis
de trabajo: las 48 selecciones del Mundial 2026 más 16 que completan los cupos
por confederación.

---

## 7. Trazabilidad (RNF5)

| Decisión de este hito | Criterio del Hito 2 | Requisito del Hito 3 |
|---|---|---|
| MongoDB como motor | Matriz Sección 3: modelo documental para entidades de estado con atributos semiestructurados, recuperadas por ID sin joins | Sección 1: *"Documental — MongoDB"* para equipos, jugadores y alineaciones |
| Referencias en vez de embedding | *"Se recupera la entidad completa por ID en una sola lectura"* — aplicado al jugador como entidad propia | Sección 1: los eventos en Neo4j (`ANOTA`, `ASISTE`, `REEMPLAZA`, `PARTICIPA`) referencian jugadores desde otro subsistema |
| Desnormalización parcial aceptable | Criterio 2 de la Sección 2 (adecuación al patrón de acceso, peso 20 %): lectura frecuente, escritura ocasional | Sección 2 (CAP): esquema **AP** con consistencia eventual declarada explícitamente para Equipos y Jugadores |
| Sin sharding; índices modestos | Criterio 3 (escalabilidad, 20 %): el volumen no fue el factor determinante para este subsistema | Sección 3: *"No se particiona porque el volumen no lo justifica"* |
| Identificador de negocio como `_id` | Matriz: *"recuperados principalmente por ID"* | Sección 3: *"El acceso es de lectura frecuente por ID y escritura ocasional"* |
| Validación estricta en el motor | Criterio 5 (consistencia, 10 %): distintos datos requieren distintos niveles de integridad | — (requisito propio del Hito 4: RF7 y RNF3) |
| Replicación expresada en vocabulario de MongoDB | Criterio 7 (disponibilidad y resiliencia, 10 %): objetivo de 99,99 % | Sección 3, **revisado** — ver §5 de este documento |

**Cifras utilizadas.** Este módulo cita 64 equipos y "más de 1.500 jugadores",
ambas confirmadas por el enunciado del Hito 4 (*"El Fixture 2030 reúne 64
selecciones nacionales y más de 1.500 jugadores"*) y coincidentes con la tabla de
volúmenes del Hito 1. No se citan cifras de Partidos ni de Eventos; de ser
necesario en entregas posteriores, los valores vigentes son **127 partidos** y
**1.000+ eventos por partido**, que corrigen los de la tabla original del Hito 1.

---

## 8. Verificación

El diseño se comprueba, no se declara. Los resultados están en `evidencia/`
(`ambiente.txt`, `carga.txt`, `verificacion.txt`):

| Requisito | Cómo se verifica | Resultado |
|---|---|---|
| RF4 — 64 equipos | `04-verificar-integridad.js` | 64 |
| RF5 — ≥ 1.000 jugadores | `04-verificar-integridad.js` | 1.664 |
| RF7 — Validación de atributos críticos | `04-verificar-integridad.js` comprueba que ambas colecciones tengan validador activo | `validationAction: error` en las dos |
| RF8 — Carga idempotente | Segunda corrida de `cargar.sh` | `matched 1664, upserted 0, modified 0` |
| RNF3 — Sin IDs duplicados | Agregación por nombre y por (equipo, dorsal) | 0 duplicados |
| RNF3 — Sin jugadores huérfanos | `$nin` contra los `_id` de equipos | 0 huérfanos |
| RNF3 — Sin campos críticos ausentes | Conteo por `$or` de nulos | 0 incompletos |
| RNF3 — Snapshot sincronizado | `$lookup` + `$expr` contra la fuente | 0 desfasados |
| RF1 — MongoDB disponible | `evidencia-ambiente.sh`: `ping`, versión y uptime | `ping: 1`, MongoDB 7.0.40 |
| RF2 — Persistencia | `docker compose restart` y reconteo | 64 / 1.664 antes y después |
| Reproducibilidad del generador | Borrado y recarga, comparación documento a documento | Idénticos |

---

## 9. Operaciones y consultas (Ítem 4)

Las 7 operaciones documentales implementadas en `mongo/05-operaciones-consultas.js` y ejecutadas mediante `scripts/consultar.sh` responden a los casos de uso esenciales del módulo:

1. **Inserción (`insertOne`).** Alta de un nuevo equipo invitado (`NZL`) y un nuevo jugador (`NZL-9`). Valida de forma estricta el cumplimiento del `$jsonSchema`: tipos enteros `Int32` BSON (`ranking_fifa`, `dorsal`, `altura_cm`), formato de fecha `ISODate`, y presencia obligatoria del subdocumento desnormalizado `equipo` (`_id`, `nombre`, `confederacion`).
2. **Recuperación por identificador (`findOne`).** Lectura de tiempo $O(1)$ por identificador natural de negocio: `_id: "ARG"` para equipos y `_id: "ARG-10"` para jugadores. Ambas operaciones aprovechan el índice primario clustered provisto por defecto por MongoDB, sin sobrecosto de índices secundarios.
3. **Recuperación filtrada (`find`).** Consultas con lógica compuesta de negocio:
   - Equipos: Selecciones de `CONMEBOL` con `ranking_fifa <= 15` para determinar cabezas de serie del torneo.
   - Jugadores: Búsqueda sobre campos simples y subdocumentos (`posicion: "Delantero"`, `equipo.confederacion: "UEFA"`, `altura_cm >= 188`) para identificar futbolistas de gran porte físico.
4. **Proyección (`find` con segundo argumento de campos).** Optimización del payload de red para las tarjetas de alineación. Se proyectan únicamente `dorsal`, `nombre`, `apellido`, `club` y `equipo.nombre`, suprimiendo explícitamente el campo `_id: 0`. Esto reduce el uso de memoria en el cliente y ahorra ancho de banda.
5. **Ordenamiento y paginación (`sort`, `skip`, `limit`).** Navegación determinista para el directorio de más de 1.600 jugadores. Cargar la totalidad de la colección en una petición bloquearía el hilo de renderizado de la UI; la paginación (`limit: 5`, `skip: 5`) segmenta la transferencia. El orden alfabético `{ apellido: 1, nombre: 1 }` está cubierto al 100 % por el índice `idx_jugadores_apellido_nombre` definido en el setup, evitando un ordenamiento costoso en memoria RAM (`SORT`).
6. **Actualización atómica (`updateOne`).**
   - En `equipos`: Actualización del director técnico mediante `$set` e incremento de participaciones mundiales mediante `$inc`.
   - En `jugadores`: Modificación de `club` y `peso_kg` con `$set`, manteniendo inalterado el subdocumento `equipo` para no generar desfasajes con el documento padre.
7. **Agregación analítica (`aggregate`).** Pipeline de visión consolidada de los planteles anfitriones del Mundial 2030:
   - `$match`: Filtra únicamente selecciones anfitrionas (`anfitrion: true`).
   - `$lookup`: Realiza el cruce con `jugadores` uniendo por `_id` y `equipo._id`.
   - `$unwind`: Descompone el array del plantel resultante.
   - `$group`: Agrupa por selección y calcula el total de convocados (`$sum`) y las métricas físicas promedio (`$avg` de altura y peso).
   - `$project`: Redondea los promedios (`$round`) y genera la estructura para el reporte final.
   - `$sort` y `$limit`: Ordena descendentemente por estatura media y limita la salida a los anfitriones.

---

## 10. Análisis de rendimiento y reevaluación de índices (Ítem 5)

En la Sección 4 se documentó el principio de diseño: *"los candidatos sin evidencia quedan fuera a propósito: el costo de escritura solo se justifica contra una consulta medida"*, dejando deliberadamente sin indexar campos como `club` y `fecha_nacimiento`.

El script `scripts/rendimiento.sh` (basado en `mongo/06-analisis-rendimiento.js`) implementa la comprobación formal del ciclo de optimización sobre la consulta crítica:
`db.jugadores.find({ club: "Real Madrid" }).sort({ fecha_nacimiento: 1 })`

### 10.1. Diagnóstico previo (sin índice)
Al ejecutar `.explain("executionStats")`:
- **Stage del Winning Plan:** `SORT` precedido por un escaneo total `COLLSCAN`.
- **totalDocsExamined:** **1.664 documentos** (el 100 % de la colección de jugadores).
- **totalKeysExamined:** **0**.
- **nReturned:** **35 documentos**.
- **Diagnóstico:** Para encontrar los 35 jugadores del club, el motor debió recorrer cada documento en disco/memoria (`COLLSCAN`) y luego almacenar los resultados intermedios para ordenarlos por fecha de nacimiento en memoria RAM (`SORT`), excediendo trabajo y violando la regla de escalabilidad si el volumen creciera.

### 10.2. Creación del índice compuesto
Se aplicó la regla ESR (*Equality, Sort, Range*) creando un índice compuesto:
```javascript
db.jugadores.createIndex(
  { club: 1, fecha_nacimiento: 1 },
  { name: "idx_jugadores_club_nacimiento" }
);
```
**Razonamiento:** El primer campo (`club`) resuelve la igualdad del filtro por búsqueda en B-Tree. El segundo campo (`fecha_nacimiento`) permite que el cursor recorra las claves ya ordenadas directamente desde el árbol del índice, eliminando por completo la necesidad del stage `SORT` en memoria.

### 10.3. Medición posterior (con índice aplicado)
Al repetir `.explain("executionStats")`:
- **Stage del Winning Plan:** `FETCH` alimentado por un `IXSCAN` directo sobre `idx_jugadores_club_nacimiento`.
- **totalKeysExamined:** **35**.
- **totalDocsExamined:** **35**.
- **nReturned:** **35**.
- **Eliminación de etapa `SORT`:** El ordenamiento se resuelve implícitamente por el recorrido del índice.
- **Conclusión de rendimiento:** La relación entre documentos examinados y devueltos alcanzó la eficiencia ideal de 1:1 (`totalDocsExamined == nReturned`), reduciendo los accesos a disco de 1.664 a únicamente 35 registros. La evidencia cruda completa queda registrada en `evidencia/rendimiento.txt`.

