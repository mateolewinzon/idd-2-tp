# Decisiones del módulo de grafos — Fixture 2030 (Hito 5)

## 1. Datos cargados

### 1.1. Origen

| Archivo (`import/`) | Filas | Origen | Se carga como |
| ------------------- | ----- | ------ | ------------- |
| `equipos.csv` | 64 | Colección `equipos` de MongoDB (Hito 4) | Nodos `Equipo` |
| `jugadores.csv` | 1.664 | Colección `jugadores` de MongoDB (Hito 4) | Nodos `Jugador` y `PERTENECE_A` |
| `sedes.csv` | 20 | Generado | Nodos `Sede` |
| `partidos.csv` | 127 | Generado | Nodos `Partido` y `SE_DISPUTA_EN` |
| `participaciones.csv` | 254 | Generado | `PARTICIPA_EN` |
| `alineaciones.csv` | 3.826 | Generado | `ALINEADO_EN` |
| `eventos.csv` | 1.869 | Generado | Nodos `Evento` y `OCURRE_EN` |
| `protagonistas.csv` | 3.155 | Generado | `PROTAGONIZA` |

Los ocho archivos los produce `scripts/generar-csv.js`, que `scripts/generar-csv.sh`
ejecuta con mongosh dentro del contenedor de MongoDB del Hito 4. Los CSV quedan
versionados en `import/`: la carga en Neo4j no depende de MongoDB, que solo hace
falta para regenerarlos.

- **Equipos y jugadores se leen de las colecciones.** Los `id` del grafo son los
  `_id` de MongoDB (RF5), y partidos, alineaciones y eventos se generan sobre esos
  mismos jugadores: no puede aparecer un equipo o un jugador inexistente.
- **Generación determinista.** Es la misma técnica del Hito 4
  (`03-carga-jugadores.js`): cada partido siembra su generador con un hash de su
  `id`. Dos corridas sobre la misma base producen archivos idénticos, y
  `generar-csv.sh` lo comprueba en cada ejecución: genera los ocho archivos dos
  veces y compara las dos pasadas (salida en `evidencia/generacion.txt`).

### 1.2. Criterios de generación

- **Sedes.** 20 estadios de los seis países anfitriones. Los tres sudamericanos
  reciben solo el primer partido de grupo de su anfitrión (Uruguay, Argentina y
  Paraguay: los partidos del centenario que menciona `equipos.js` del Hito 4). El
  resto del torneo se juega en España, Portugal y Marruecos.
- **Fase de grupos (96 partidos).** Todos contra todos en tres jornadas, con los
  equipos de cada grupo ordenados por ranking FIFA. Cada grupo juega en dos sedes
  (tres si tiene un partido del centenario), y los dos partidos de cada jornada se
  reparten entre ellas: ninguna sede recibe dos partidos el mismo día. Jornadas del
  11 al 24 de junio de 2030, más los tres partidos del centenario del 8
  al 10 de junio.
- **Eliminación directa (31 partidos).** Clasifican los dos primeros de cada grupo
  (por puntos, diferencia de gol, goles a favor y ranking FIFA). En dieciseisavos, el
  primero de un grupo enfrenta al segundo del grupo vecino, y las dos mitades del
  cuadro solo se cruzan en la final. Las rondas finales se concentran en menos
  estadios; la final se juega el 21 de julio en el Estadio Santiago Bernabeu. Es local
  el equipo de mejor ranking FIFA.
- **Cada partido.** Formación 1-4-3-3, con preferencia por los dorsales más bajos
  de cada puesto. Entre 3 y 5 cambios por equipo, en el segundo tiempo. Los goles
  salen de 6 ocasiones por equipo, cada una con una probabilidad que depende de la
  diferencia de ranking FIFA, y cada gol tiene asistencia con un 70 % de
  probabilidad. Entre 2 y 5 tarjetas
  amarillas por partido, y una roja en uno de cada ocho partidos, aproximadamente.
  En eliminación directa un empate se define con un gol en la prórroga (minuto 91 a
  120); no se modelan penales ni goles en contra.
- **Cronología coherente.** Solo puede protagonizar un evento un jugador que está en
  la cancha en ese minuto, y un expulsado no tiene acciones posteriores.
- **Textos.** Nombres sin tildes, como en los datos del Hito 4 (`Espana`,
  `Asuncion`, `Estadio Santiago Bernabeu`). Los valores de `tipo`, `rol` y `fase`
  son los del modelo (`docs/modelo_grafo.md`), incluida la tilde de `Sustitución`;
  las consultas tienen que usarlos escritos exactamente así.

### 1.3. Controles de coherencia

El generador verifica lo siguiente y, si algo falla, termina con error y no
reemplaza el CSV anterior:

- MongoDB tiene 64 equipos y al menos 1.000 jugadores; cada jugador referencia un
  equipo existente, y cada grupo tiene 4 equipos.
- Hay 127 partidos con `id` único y ningún equipo juega contra sí mismo. En fase de
  grupos, los dos equipos pertenecen al grupo del partido. Ninguna sede recibe dos
  partidos el mismo día.
- En cada partido, cada equipo tiene 11 titulares y a lo sumo 5 cambios, y ningún
  jugador aparece alineado dos veces.
- Los protagonistas corresponden al tipo de evento (`Gol`: autor y asistencia
  opcional; `Sustitución`: sale y entra; `Tarjeta Amarilla`: amonestado;
  `Tarjeta Roja`: expulsado), y cada protagonista jugó el partido del evento.
- Cada equipo juega entre 3 y 8 partidos, y los eventos entran en el formato
  `E-XXXX`.

### 1.4. Resultado

La cantidad de filas por archivo queda en `evidencia/generacion.txt`. Para
interpretar las consultas:

- 370 goles (2,91 por partido), 7 de ellos en prórroga; 450 tarjetas amarillas, 17
  rojas y 1.032 sustituciones.
- 28 goles de un titular asistido por un compañero que ingresó desde el banco: la
  pregunta 3 tiene resultados que verificar.

## 2. Carga en Neo4j

### 2.1. Método

`queries/carga.cypher` recorre cada CSV con `LOAD CSV WITH HEADERS FROM ... AS fila`
(encontrado en documentación Neo4j Docs) y, por cada fila, hace `MERGE` sobre el
`id` del nodo o sobre los dos nodos de la relación, y `SET` para el resto de las
propiedades — el mismo patrón que `docs/modelo_grafo.md` §5.2 documenta y justifica.
Los nodos se cargan primero (uno por archivo) y las relaciones después, cada una en
su propia sentencia `LOAD CSV`, así que un archivo con relaciones nunca se procesa
antes de que existan los dos nodos que conecta.

Dos conversiones de tipo, porque `LOAD CSV` entrega todo como texto:

- `fecha` se convierte con `date()` (Clase 5).
- `minuto` se convierte con `toInteger()` (encontrado en documentación Neo4j Docs),
  para poder compararlo y ordenarlo como número.
- `titular` se resuelve comparando el texto contra `'true'`, sin una función de
  conversión adicional.

### 2.2. Evidencia de idempotencia (RNF4)

`scripts/cargar.sh` ejecuta `queries/verificacion.cypher` antes de cargar, después
de la primera carga y después de repetirla, y compara las dos últimas salidas. La
corrida quedó en `evidencia/carga.txt`:

| Elemento | Conteo |
| -------- | -----: |
| `Equipo` | 64 |
| `Jugador` | 1.664 |
| `Sede` | 20 |
| `Partido` | 127 |
| `Evento` | 1.869 |
| `PERTENECE_A` | 1.664 |
| `SE_DISPUTA_EN` | 127 |
| `PARTICIPA_EN` | 254 |
| `ALINEADO_EN` | 3.826 |
| `OCURRE_EN` | 1.869 |
| `PROTAGONIZA` | 3.155 |

Coinciden exactamente con las filas de cada CSV (§1.1): cada fila generó un nodo o
una relación, sin duplicados. Los cinco controles de coherencia (jugadores sin
equipo, partidos sin sede, partidos sin equipos, eventos sin partido, eventos sin
protagonista) dieron 0 antes y después de repetir la carga.

## 3. Operaciones CRUD

`queries/crud.cypher` demuestra las cuatro operaciones pedidas sobre una sede y un
partido de prueba: los crea con `MERGE`, recupera el patrón, actualiza el nombre de
la sede, elimina la relación y finalmente elimina los dos nodos. Los identificadores
`DEMO-SEDE` y `DEMO-PARTIDO` están reservados para esta prueba.

El borrado es deliberadamente seguro: tanto la relación como los nodos se buscan
por sus identificadores exactos. No se usa un patrón general como
`MATCH (n) DETACH DELETE n`, que borraría el grafo completo. Al terminar, dos
consultas de control devuelven cero relaciones y cero nodos de demostración.

## 4. Preguntas de grafo y valor para el sistema

`queries/consultas_grafo.cypher` contiene cinco consultas:

1. **Máximos goleadores de Argentina.** Recorre
   `Equipo <- Jugador -> Evento` y agrupa los goles por jugador.
2. **Jugadores de CONMEBOL que anotaron en el Bernabeu.** Recorre
   `Equipo <- Jugador -> Evento -> Partido -> Sede`, filtrando los extremos del
   recorrido por confederación y sede.
3. **Titulares asistidos por un suplente.** Une autor, asistente, gol, partido,
   alineaciones y equipo para comprobar que fueron compañeros y que el autor fue
   titular mientras el asistente ingresó desde el banco.
4. **Programación de la final.** Recupera los dos participantes, la fecha y la sede
   de un partido mediante sus relaciones.
5. **Conectividad de sedes.** Ordena las sedes por cantidad de equipos distintos
   conectados a través de los partidos que recibieron.

Las consultas 1, 2 y 3 satisfacen el requisito de múltiples saltos (RF8). La quinta
es el análisis de conectividad (RF9): identifica qué estadios concentran mayor
diversidad de participantes. Ese dato aporta al negocio porque permite priorizar
capacidad operativa, transporte, seguridad, atención al público y acciones
comerciales en los puntos de encuentro más centrales del torneo. No intenta medir
la importancia deportiva de una sede, sino su alcance dentro del fixture cargado.

El resultado verificable sobre los datos entregados ubica primero al **Gran Estadio
Hassan II (`S-15`)**, conectado con **14 equipos distintos** mediante **10
partidos**. Luego aparecen Camp Nou (`S-06`) con 13 equipos y el Estadio da Luz
(`S-12`) con 12. Estos valores se derivan del fixture generado y pueden cambiar si
se regeneran los partidos con otros criterios.

Como control contra los CSV entregados, los otros resultados esperados son:

- Argentina: `ARG-4` encabeza con 2 goles; los siguientes jugadores tienen 1.
- CONMEBOL en el Bernabeu: 4 goles, todos de Brasil, en `P-113` y `P-121`.
- Titular asistido por un suplente: 28 goles.
- Final: Inglaterra contra Alemania (`P-127`), el 21/07/2030 en el Bernabeu.

Estos controles no reemplazan la ejecución en Neo4j: sirven para detectar de forma
simple si una consulta devuelve filas de más, de menos o con relaciones incorrectas.

### 4.1. Por qué estas preguntas justifican un grafo

En MongoDB, equipo, jugador, partido, evento, sede y alineación quedarían en
documentos o colecciones distintas. Resolver las preguntas 2 y 3 obligaría a hacer
varios cruces encadenados o a duplicar de antemano los datos de cada relación. En
Neo4j esos vínculos son parte del modelo: la consulta describe directamente el
camino que se quiere recorrer.

El beneficio se nota especialmente en la pregunta 3. No basta con buscar goles:
hay que unir dos protagonistas del mismo evento, verificar la alineación de ambos
en el mismo partido y comprobar que pertenecen al mismo equipo. En la consulta 5,
la conectividad tampoco es una propiedad fija de la sede; surge de recorrer
`Sede <- Partido <- Equipo` y contar vecinos distintos. Si cambia el fixture, el
resultado cambia sin tener que mantener un contador duplicado dentro de la sede.

MongoDB sigue siendo apropiado para recuperar la ficha completa de un equipo o un
jugador. Neo4j se usa aquí solo para las preguntas cuyo valor está en navegar las
relaciones, tal como se trabajó en la Clase 5.

## 5. Evidencia

- `evidencia/carga.txt`: carga repetida y conteos que prueban idempotencia.
- `evidencia/crud.txt`: lo genera `scripts/crud.sh` con los resultados del CRUD y
  los controles de borrado.
- `evidencia/consultas.txt`: lo genera `scripts/consultar.sh` con las salidas
  tabulares y la representación textual de los caminos de visualización.
- Para la vista gráfica, el último bloque de `queries/consultas_grafo.cypher`
  devuelve únicamente el subgrafo de la final. En Neo4j Browser se ejecuta ese
  bloque y se selecciona la vista **Graph**, evitando una visualización ilegible de
  todo el grafo.
