# Modelo de grafo — Fixture 2030 (Hito 5)

## 1. El problema relacional

El módulo documental del Hito 4 recupera un equipo o un jugador completo por su
identificador. Las preguntas de este hito son de otro tipo: no piden una entidad,
piden el **camino** que une a varias. Con documentos aislados habría que encadenar
una búsqueda entre colecciones por cada salto (como el cruce entre equipos y
jugadores de la agregación del Hito 4) o copiar las relaciones dentro de cada
documento de antemano. En un grafo la relación queda guardada de forma explícita y
la consulta es el mismo patrón que se quiere recorrer. Es el motivo por el que el
Hito 2 eligió Neo4j para esta información: *"el valor del evento está en las
relaciones [...]; Neo4j las recorre en consultas multi-salto sin joins"*. La Clase 5
agrega que *"el costo de recorrer una relación es fijo"* y que *"el tiempo de
consulta no depende del tamaño total de la base de datos, sino del tamaño del
subgrafo recorrido"*.

Preguntas que motivan el modelo:

| # | Pregunta | Recorrido en el grafo | Por qué no alcanza un documento aislado |
| - | -------- | --------------------- | --------------------------------------- |
| 1 | ¿Quién fue el máximo goleador de un equipo? | `Equipo ← Jugador → Evento (Gol)` | El gol está en el evento y el equipo en el jugador: son dos saltos entre entidades distintas. |
| 2 | ¿Qué equipo anotó más goles en el torneo? | `Equipo ← Jugador → Evento (Gol)` | Mismo recorrido que la 1, agrupado por equipo. |
| 3 | ¿Qué jugadores titulares convirtieron goles asistidos por un compañero que ingresó desde el banco en ese mismo partido? | `(autor)-[:PROTAGONIZA {rol: 'autor'}]->(g:Evento {tipo: 'Gol'})<-[:PROTAGONIZA {rol: 'asistencia'}]-(asistente)`, `(g)-[:OCURRE_EN]->(p:Partido)`, y autor y asistente `-[:ALINEADO_EN]->(p)` con `titular` `true` y `false` | Une la alineación de dos jugadores con un mismo gol y un mismo partido: cuatro elementos en un solo patrón. |
| 4 | ¿Qué jugadores de la confederación X anotaron goles en la sede Y? | `Equipo (confederacion) ← Jugador → Evento (Gol) → Partido → Sede` | Atraviesa cinco entidades; con documentos serían cuatro búsquedas encadenadas. |
| 5 | ¿Qué partidos se juegan en una fase del torneo, entre qué equipos y en qué sedes? | `Equipo → Partido (fase) → Sede` | Programación del fixture: los dos equipos y la sede de cada partido son entidades distintas, unidas por el partido. |
| 6 | ¿Qué sede fue el principal punto de encuentro del torneo, recibiendo la mayor cantidad de equipos distintos? | `Sede ← Partido ← Equipo` | Consulta de análisis: mide la conectividad de cada sede contando los equipos distintos que llegan a ella. |

Las preguntas 3 y 4 son las consultas obligatorias de dos o más relaciones
consecutivas (RF8); la 6 es la consulta de conectividad (RF9).

## 2. Nodos y propiedades

| Etiqueta | Identificador (`id`) | Otras propiedades | Origen | Cantidad esperada |
| -------- | -------------------- | ----------------- | ------ | ----------------- |
| `Equipo` | Código FIFA, ej. `"ARG"` | `nombre`, `confederacion`, `grupo` | Colección `equipos` de MongoDB (Hito 4) | 64 |
| `Jugador` | `<código FIFA>-<dorsal>`, ej. `"ARG-10"` | `nombre`, `apellido`, `posicion` | Colección `jugadores` de MongoDB (Hito 4) | 1.664 (26 por equipo) |
| `Partido` | `P-XXX`, ej. `"P-001"` | `fase`, `grupo` (solo en fase de grupos), `fecha` | Generado para este hito | 127 |
| `Sede` | `S-XX`, ej. `"S-01"` | `nombre`, `ciudad`, `pais` | Generado: estadios de los seis países anfitriones | 20 |
| `Evento` | `E-XXXX`, ej. `"E-0001"` | `tipo` (`Gol`, `Tarjeta Amarilla`, `Tarjeta Roja`, `Sustitución`), `minuto` | Generado: muestra por partido | ≈15 por partido (1.869) |

Decisiones sobre los nodos:

- **Misma identidad que en MongoDB (RF5).** El `id` de `Equipo` y de `Jugador` es
  exactamente el `_id` del documento en MongoDB: `Equipo.id = equipos._id` y
  `Jugador.id = jugadores._id`. La propiedad se llama `id` en el grafo, pero el valor
  es el mismo, así que `"ARG-10"` identifica al mismo jugador en los dos módulos.
- **MongoDB sigue siendo la fuente de verdad de equipos y jugadores.** El grafo copia
  solo las propiedades que las consultas filtran o muestran, o que la carga usa para
  controlar la coherencia (el `grupo` de un equipo tiene que coincidir con el `grupo`
  de sus partidos de fase de grupos). Club, fecha de nacimiento, datos físicos y
  director técnico quedan en MongoDB.
- **La copia se actualiza volviendo a cargar, no por sincronización.** El Hito 5 no
  exige integrar por código los dos módulos, sino *"consistencia semántica y de
  identificadores"* (§6). Si cambia una propiedad en MongoDB, se refleja en el
  grafo volviendo a ejecutar la carga, que es idempotente. La carga agrega y
  actualiza, pero no borra: si un jugador sale del plantel o se recrea con otro `_id`
  (Hito 4, §6.2), su nodo anterior se elimina con un `DETACH DELETE` filtrado por
  `id` en `queries/crud.cypher` (Clase 5), y los conteos de la sección 5.2 delatan
  cualquier nodo sobrante. Entre una carga y la siguiente la copia puede quedar
  desactualizada: se extiende a esta copia el criterio que el
  Hito 3 aceptó para equipos y jugadores, donde las pocas escrituras pueden no verse
  reflejadas de inmediato.
- **Partidos y eventos viven solo en Neo4j**, como define el Hito 3 y registra el
  §1.1 del documento del Hito 4.
- **127 partidos:** 96 de fase de grupos (16 grupos de 4 equipos, 6 partidos por
  grupo) y 31 de eliminación directa (dieciseisavos 16, octavos 8, cuartos 4,
  semifinales 2, final 1), sin partido por el tercer puesto. Es la cifra de la
  cátedra y corrige los ~175 del Hito 1, como ya se indicó en el Hito 4.
  La propiedad `fase` toma los valores `Grupos`, `Dieciseisavos`, `Octavos`,
  `Cuartos`, `Semifinal` y `Final`.
- **Sedes:** 20 estadios de los seis países anfitriones: uno en cada país
  sudamericano (Uruguay, Argentina y Paraguay) y 17 entre España, Portugal y
  Marruecos. Ejemplo: `S-01`, Estadio Centenario,
  Montevideo, Uruguay. La asignación de partidos a sedes la fija el generador con el
  criterio de `docs/decisiones.md` (§1.2), y el resultado de la pregunta 6 se
  interpreta sobre esa asignación.
- **Eventos:** se carga una muestra de goles, tarjetas y sustituciones: 1.869
  eventos, alrededor de 15 por partido (detalle en `docs/decisiones.md`). Pases, tiros o
  recuperaciones no se modelan: sumarían volumen sin agregar relaciones que usen las
  preguntas de la sección 1. La cifra vigente para el torneo completo es de 1.000+
  eventos por partido, como registra el documento del Hito 4 al corregir los 5.000 a
  10.000 del Hito 1.
- **Sin goles en contra en la muestra.** El gol se atribuye al equipo de su autor a
  través de `PERTENECE_A`; un gol en contra sumaría para el equipo equivocado.
- **La asistencia no es un evento propio.** Se descartó modelarla como un `tipo` de
  evento separado: quedaría desvinculada del gol y no se podría saber a qué gol
  corresponde. Es un rol dentro del evento `Gol` (sección 3.1).

## 3. Relaciones

| Origen | Relación | Destino | Propiedades | Cardinalidad | Qué expresa |
| ------ | -------- | ------- | ----------- | ------------ | ----------- |
| `Jugador` | `PERTENECE_A` | `Equipo` | — | Cada jugador pertenece a 1 equipo; cada equipo tiene 26 jugadores. | Pertenencia de jugadores a equipos (RF4). Es la misma relación que `jugadores.equipo._id` en MongoDB. |
| `Equipo` | `PARTICIPA_EN` | `Partido` | `condicion`: `Local` / `Visitante` | Cada partido tiene exactamente 2 equipos, uno `Local` y uno `Visitante`; cada equipo juega entre 3 (eliminado en grupos) y 8 partidos (finalista). | Participación de equipos en partidos (RF4). |
| `Partido` | `SE_DISPUTA_EN` | `Sede` | — | Cada partido se juega en 1 sede; cada sede recibe varios partidos. | Programación de partidos en una sede (RF4). |
| `Evento` | `OCURRE_EN` | `Partido` | — | Cada evento ocurre en 1 partido; cada partido tiene 0 o más eventos. | Vinculación de eventos con su partido (RF4). |
| `Jugador` | `PROTAGONIZA` | `Evento` | `rol`: `autor`, `asistencia`, `amonestado`, `expulsado`, `sale`, `entra` | Cada evento tiene 1 o 2 protagonistas (ver 3.1); cada jugador protagoniza 0 o más eventos. | Qué jugador hizo qué en cada acción del partido. |
| `Jugador` | `ALINEADO_EN` | `Partido` | `titular`: `true` / `false` | Cada partido tiene 22 titulares y hasta 10 ingresos desde el banco (el generador limita a 5 cambios por equipo); cada jugador está alineado en 0 a 8 partidos. | Qué jugadores jugaron cada partido y si fueron titulares (ver 3.2). |

Volumen esperado de relaciones: 1.664 `PERTENECE_A`, 254 `PARTICIPA_EN`
(127 × 2), 127 `SE_DISPUTA_EN` y entre 2.794 (127 × 22, solo titulares) y 4.064
`ALINEADO_EN`. `OCURRE_EN` es igual a la cantidad de eventos, y `PROTAGONIZA` está
entre esa cantidad y el doble.

`PARTICIPA_EN` es la relación que pide RF4 para la participación de equipos en
partidos; no es la `PARTICIPA` del Hito 2 (ver 3.1).

### 3.1. `PROTAGONIZA` en lugar de `ANOTA`, `ASISTE` y `REEMPLAZA`

El Hito 2 nombró las relaciones de los eventos como `ANOTA`, `ASISTE`, `REEMPLAZA` y
`PARTICIPA`. Este modelo conserva lo que expresan, pero no las usa como tipos
separados: hay un único tipo `PROTAGONIZA`, y la propiedad `rol` indica qué hizo el
jugador en el evento.

| Hito 2 | Este modelo |
| ------ | ----------- |
| `ANOTA` | `(Jugador)-[:PROTAGONIZA {rol: 'autor'}]->(Evento {tipo: 'Gol'})` |
| `ASISTE` | `(Jugador)-[:PROTAGONIZA {rol: 'asistencia'}]->(Evento {tipo: 'Gol'})`, sobre el mismo evento del gol |
| `REEMPLAZA` | Un `Evento {tipo: 'Sustitución'}` con un jugador `rol: 'sale'` y otro `rol: 'entra'` |
| `PARTICIPA` | El Hito 2 la lista entre las relaciones del evento sin detallarla. Su lectura natural es "el jugador participa en el evento", y eso ya lo cubre `PROTAGONIZA` en general |

Protagonistas por tipo de evento: `Gol` tiene 1 `autor` y, opcionalmente, 1
`asistencia`; `Sustitución` tiene 1 `sale` y 1 `entra`; `Tarjeta Amarilla` tiene 1
`amonestado` y `Tarjeta Roja`, 1 `expulsado`.

Por qué un solo tipo:

- **El tipo de acción ya está en el evento.** `Evento` es un nodo con `tipo`;
  repetir esa información en el tipo de relación la duplicaría.
- **Una sola forma de consultar.** "Todas las acciones de un jugador" es un único
  patrón, `(Jugador)-[:PROTAGONIZA]->(Evento)`. Agregar un tipo de evento nuevo solo
  suma valores de `tipo` y `rol`, y las consultas existentes lo siguen cubriendo.
- **El gol y su asistencia quedan en el mismo nodo.** Es lo que permite responder la
  pregunta 3.

Costo aceptado: para distinguir al autor del asistente hay que filtrar por la
propiedad `rol` en lugar de por el tipo de relación.

### 3.2. `ALINEADO_EN`: la parte de la alineación que necesita el grafo

`ALINEADO_EN` no viene del Hito 2: se agrega por la pregunta 3. El Hito 3 asigna las
alineaciones a MongoDB (aunque el Hito 4 solo implementó equipos y jugadores), y el
Hito 1 descartó el grafo para ellas porque sus consultas eran simples. La pregunta 3
no lo es: cruza la titularidad de dos jugadores con un mismo gol. Por eso el grafo
guarda solo la parte de la alineación que ese recorrido necesita: qué jugadores
jugaron cada partido y si fueron titulares. La relación se crea únicamente para
jugadores que entraron a la cancha, así que `titular: false` significa "ingresó
desde el banco". La alineación completa (convocados, posición en el partido, minutos
jugados) queda fuera del grafo.

Como la colección de alineaciones todavía no existe en MongoDB, estos datos se
generan para este hito. Cuando exista, `ALINEADO_EN` será una proyección de ella y
esa parte quedará duplicada entre los dos módulos, con la misma política que el resto
de la copia: se actualiza volviendo a ejecutar la carga.

### 3.3. Direcciones

Cada relación tiene una dirección fija, elegida para que el patrón se lea como una
frase: el jugador *pertenece a* un equipo, el partido *se disputa en* una sede, el
evento *ocurre en* un partido. La dirección no limita las consultas: un patrón puede
recorrer la relación en sentido inverso (`(product)<-[:BOUGHT]-(otherUser:User)` en
la Clase 5) o sin flecha (`-[:AMIGO_DE]-` en la Clase 2). Fijar una sola dirección
evita crear la misma relación dos veces, una en cada sentido.

## 4. Diagrama del subgrafo

```
(Jugador) ──PERTENECE_A──────────────────► (Equipo)
   │  │                                       │
   │  └──ALINEADO_EN {titular}─────┐          │ PARTICIPA_EN {condicion}
   │                               ▼          │
   │                           (Partido) ◄────┘
   │ PROTAGONIZA {rol}           ▲   │
   ▼                             │   │ SE_DISPUTA_EN
(Evento) ──OCURRE_EN─────────────┘   ▼
                                  (Sede)
```

## 5. Decisiones de integridad

### 5.1. Restricciones de unicidad

`queries/estructura.cypher` crea una restricción de unicidad sobre el `id` de cada
etiqueta, antes de cargar cualquier dato:

| Etiqueta | Restricción | Garantiza |
| -------- | ----------- | --------- |
| `Equipo` | `equipo_id_unique` | No hay dos equipos con el mismo código FIFA. |
| `Jugador` | `jugador_id_unique` | No hay dos jugadores con el mismo `<código FIFA>-<dorsal>`. |
| `Partido` | `partido_id_unique` | No hay dos partidos con el mismo `P-XXX`. |
| `Sede` | `sede_id_unique` | No hay dos sedes con el mismo `S-XX`. |
| `Evento` | `evento_id_unique` | No hay dos eventos con el mismo `E-XXXX`. |

La restricción la aplica el motor: rechaza cualquier escritura que intente crear un
segundo nodo con un `id` existente, sin importar desde dónde se envíe. Es el mismo
criterio del Hito 4 para el `$jsonSchema`: el motor es el único punto que ningún
cliente puede saltear. La salida de `SHOW CONSTRAINTS` está en
`evidencia/estructura.txt`.

### 5.2. Cómo se evita duplicar identificadores

1. **Identificadores de negocio, no generados por la base.** Los `id` de `Equipo` y
   `Jugador` salen de los `_id` de MongoDB. Los de `Partido`, `Sede` y `Evento`
   tienen formato fijo y los produce un generador determinista, así que cada corrida
   genera los mismos identificadores. Es el mismo argumento de idempotencia del
   Hito 4.
2. **`MERGE` sobre el identificador y `SET` para el resto.** La carga hace
   `MERGE (e:Equipo {id: ...})` y después `SET e.nombre = ...`, como en la Práctica 2
   de la Clase 5. Si el `MERGE` incluyera todas las propiedades, un nombre corregido
   haría que no encontrara el nodo existente e intentara crear otro con el mismo `id`:
   la restricción lo rechazaría y la carga fallaría.
3. **Las relaciones también usan `MERGE`.** Las restricciones de `estructura.cypher`
   son todas de nodo (`entityType` `NODE` en `evidencia/estructura.txt`): ninguna
   impide duplicar una relación. Por eso cada relación se crea con `MERGE` entre dos
   nodos ya encontrados por su `id`
   (`MATCH (j:Jugador {id: ...}), (e:Equipo {id: ...}) MERGE (j)-[:PERTENECE_A]->(e)`).
   En una segunda corrida el `MERGE` encuentra la relación existente y no la duplica.
   Las propiedades de relación (`condicion`, `rol`, `titular`) se asignan con `SET`
   después del `MERGE`: si el `MERGE` incluyera la propiedad y la relación existente
   tuviera otro valor, no la encontraría y crearía una segunda relación sin dar error,
   es decir, un duplicado silencioso.
4. **Verificación.** Después de cada carga se cuentan nodos y relaciones por tipo y
   se comparan con los valores esperados de las secciones 2 y 3. Una segunda corrida
   tiene que dejar los conteos iguales (RNF4). La salida queda en `evidencia/`.

### 5.3. Índices

`CREATE INDEX` no se vio en clase; la sintaxis está tomada de la documentación de
Neo4j (ver el comentario en `queries/estructura.cypher`).

- **Identificadores:** en `evidencia/estructura.txt` cada restricción de unicidad
  aparece junto con un índice del mismo nombre, así que los `id` no necesitan un
  índice adicional.
- **`evento_tipo_idx` (`Evento.tipo`):** las preguntas 1 a 4 filtran los eventos de
  tipo `Gol`: es el filtro más repetido del módulo. Con la muestra de este hito su
  aporte es chico.
- **`partido_fase_idx` (`Partido.fase`):** la pregunta 5 parte de los partidos de una
  fase, que es la forma habitual de consultar el fixture durante el torneo. Con 127
  partidos su aporte también es chico. Un índice no es una mejora automática
  (Hito 4): cada uno queda atado a una pregunta concreta.
- **Descartados:** `Equipo.confederacion` y `Sede.nombre`. Son 64 equipos y 20
  sedes: recorrerlos todos es trivial, y las consultas llegan a las sedes por su `id`
  o a través de los partidos.
