// Carga idempotente del grafo del Fixture 2030 desde los CSV de import/.
//
// Requisitos: restricciones de queries/estructura.cypher ya aplicadas y los CSV
// en import/ (carpeta montada en /var/lib/neo4j/import).
//
// Idempotencia (RNF4): cada nodo se crea con MERGE sobre su id y el resto de sus
// propiedades se asigna con SET; cada relacion se crea con MERGE entre dos nodos
// ya encontrados por id (MATCH ... MERGE, Clase 5). Volver a ejecutar el archivo
// encuentra lo que ya existe y no duplica nada (docs/modelo_grafo.md §5.2).
//
// LOAD CSV WITH HEADERS FROM ... AS fila: encontrado en documentacion Neo4j Docs
// (Cypher Manual, LOAD CSV). Recorre el CSV y entrega cada fila como un mapa
// campo -> texto.
//
// Los nodos y sus relaciones se cargan en sentencias separadas: cada sentencia es
// un solo MERGE (nodos) o un solo MATCH ... MERGE (relaciones).

// ============================================================ Nodos

// Equipos (64). id = _id del equipo en MongoDB.
LOAD CSV WITH HEADERS FROM 'file:///equipos.csv' AS fila
MERGE (e:Equipo {id: fila.id})
SET e.nombre = fila.nombre, e.confederacion = fila.confederacion, e.grupo = fila.grupo;

// Jugadores (1.664). id = _id del jugador en MongoDB.
LOAD CSV WITH HEADERS FROM 'file:///jugadores.csv' AS fila
MERGE (j:Jugador {id: fila.id})
SET j.nombre = fila.nombre, j.apellido = fila.apellido, j.posicion = fila.posicion;

// Sedes (20).
LOAD CSV WITH HEADERS FROM 'file:///sedes.csv' AS fila
MERGE (s:Sede {id: fila.id})
SET s.nombre = fila.nombre, s.ciudad = fila.ciudad, s.pais = fila.pais;

// Partidos (127). La fecha se convierte con date(), como en la Clase 5. En
// eliminacion directa el campo grupo viene vacio y el partido queda sin grupo.
LOAD CSV WITH HEADERS FROM 'file:///partidos.csv' AS fila
MERGE (p:Partido {id: fila.id})
SET p.fase = fila.fase, p.grupo = fila.grupo, p.fecha = date(fila.fecha);

// Eventos (1.869). toInteger: encontrado en documentacion Neo4j Docs (Cypher
// Manual, funciones). LOAD CSV lee todo como texto y el minuto se guarda como
// numero para poder compararlo y ordenarlo.
LOAD CSV WITH HEADERS FROM 'file:///eventos.csv' AS fila
MERGE (ev:Evento {id: fila.id})
SET ev.tipo = fila.tipo, ev.minuto = toInteger(fila.minuto);

// ============================================================ Relaciones

// (Jugador)-[:PERTENECE_A]->(Equipo)
LOAD CSV WITH HEADERS FROM 'file:///jugadores.csv' AS fila
MATCH (j:Jugador {id: fila.id}), (e:Equipo {id: fila.equipo_id})
MERGE (j)-[:PERTENECE_A]->(e);

// (Partido)-[:SE_DISPUTA_EN]->(Sede)
LOAD CSV WITH HEADERS FROM 'file:///partidos.csv' AS fila
MATCH (p:Partido {id: fila.id}), (s:Sede {id: fila.sede_id})
MERGE (p)-[:SE_DISPUTA_EN]->(s);

// (Equipo)-[:PARTICIPA_EN {condicion}]->(Partido)
LOAD CSV WITH HEADERS FROM 'file:///participaciones.csv' AS fila
MATCH (e:Equipo {id: fila.equipo_id}), (p:Partido {id: fila.partido_id})
MERGE (e)-[r:PARTICIPA_EN]->(p)
SET r.condicion = fila.condicion;

// (Jugador)-[:ALINEADO_EN {titular}]->(Partido). El CSV trae 'true' o 'false'
// como texto: la comparacion lo convierte en un valor verdadero o falso.
LOAD CSV WITH HEADERS FROM 'file:///alineaciones.csv' AS fila
MATCH (j:Jugador {id: fila.jugador_id}), (p:Partido {id: fila.partido_id})
MERGE (j)-[r:ALINEADO_EN]->(p)
SET r.titular = (fila.titular = 'true');

// (Evento)-[:OCURRE_EN]->(Partido)
LOAD CSV WITH HEADERS FROM 'file:///eventos.csv' AS fila
MATCH (ev:Evento {id: fila.id}), (p:Partido {id: fila.partido_id})
MERGE (ev)-[:OCURRE_EN]->(p);

// (Jugador)-[:PROTAGONIZA {rol}]->(Evento)
LOAD CSV WITH HEADERS FROM 'file:///protagonistas.csv' AS fila
MATCH (j:Jugador {id: fila.jugador_id}), (ev:Evento {id: fila.evento_id})
MERGE (j)-[r:PROTAGONIZA]->(ev)
SET r.rol = fila.rol;
