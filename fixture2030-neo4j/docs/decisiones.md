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
