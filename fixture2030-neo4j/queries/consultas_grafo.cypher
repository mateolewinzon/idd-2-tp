// Consultas funcionales y de analisis del Fixture 2030 (RF8 y RF9).
// Los parametros se dejan como literales para que el archivo pueda ejecutarse
// completo con cypher-shell y copiarse por bloques a Neo4j Browser.

// ============================================================ Consulta 1
// Maximos goleadores de Argentina.
// Recorrido de dos relaciones: Equipo <- Jugador -> Evento.

RETURN 'Consulta 1 - maximos goleadores de Argentina' AS seccion;

MATCH (e:Equipo {id: 'ARG'})<-[:PERTENECE_A]-(j:Jugador)
MATCH (j)-[:PROTAGONIZA {rol: 'autor'}]->(gol:Evento {tipo: 'Gol'})
RETURN j.id AS jugador_id,
       j.nombre + ' ' + j.apellido AS jugador,
       count(gol) AS goles
ORDER BY goles DESC, jugador_id
LIMIT 5;

// ============================================================ Consulta 2
// Jugadores de CONMEBOL que anotaron en el Estadio Santiago Bernabeu.
// Recorrido de cuatro relaciones entre cinco entidades:
// Equipo <- Jugador -> Evento -> Partido -> Sede.

RETURN 'Consulta 2 - goles CONMEBOL en el Bernabeu' AS seccion;

MATCH (e:Equipo {confederacion: 'CONMEBOL'})<-[:PERTENECE_A]-(j:Jugador)
MATCH (j)-[:PROTAGONIZA {rol: 'autor'}]->(gol:Evento {tipo: 'Gol'})
      -[:OCURRE_EN]->(p:Partido)-[:SE_DISPUTA_EN]->
      (s:Sede {id: 'S-04'})
RETURN j.id AS jugador_id,
       j.nombre + ' ' + j.apellido AS jugador,
       e.nombre AS equipo,
       p.id AS partido,
       gol.minuto AS minuto,
       s.nombre AS sede
ORDER BY partido, minuto, jugador_id;

// ============================================================ Consulta 3
// Goles de un titular asistidos por un companero que entro desde el banco.
// Une dos jugadores, su alineacion y un mismo evento dentro del mismo partido.

RETURN 'Consulta 3 - titular asistido por suplente' AS seccion;

MATCH (autor:Jugador)-[:PROTAGONIZA {rol: 'autor'}]->(gol:Evento {tipo: 'Gol'})
      <-[:PROTAGONIZA {rol: 'asistencia'}]-(asistente:Jugador)
MATCH (gol)-[:OCURRE_EN]->(p:Partido)
MATCH (autor)-[:ALINEADO_EN {titular: true}]->(p)
MATCH (asistente)-[:ALINEADO_EN {titular: false}]->(p)
MATCH (autor)-[:PERTENECE_A]->(e:Equipo)<-[:PERTENECE_A]-(asistente)
RETURN p.id AS partido,
       e.nombre AS equipo,
       autor.nombre + ' ' + autor.apellido AS autor,
       asistente.nombre + ' ' + asistente.apellido AS asistente,
       gol.minuto AS minuto
ORDER BY partido, minuto;

// ============================================================ Consulta 4
// Fixture de la final: equipos participantes y sede.

RETURN 'Consulta 4 - programacion de la final' AS seccion;

MATCH (local:Equipo)-[:PARTICIPA_EN {condicion: 'Local'}]->(p:Partido {fase: 'Final'})
MATCH (visitante:Equipo)-[:PARTICIPA_EN {condicion: 'Visitante'}]->(p)
MATCH (p)-[:SE_DISPUTA_EN]->(s:Sede)
RETURN p.id AS partido, p.fecha AS fecha,
       local.nombre AS local, visitante.nombre AS visitante,
       s.nombre AS sede, s.ciudad AS ciudad;

// ============================================================ Consulta 5 - analisis de conectividad
// Ranking de sedes por cantidad de equipos distintos que jugaron en ellas.
// Una sede con mayor alcance conecta a mas participantes del torneo y es un
// punto mas central para la operacion, traslados, seguridad y demanda esperada.

RETURN 'Consulta 5 - conectividad de sedes' AS seccion;

MATCH (s:Sede)<-[:SE_DISPUTA_EN]-(p:Partido)<-[:PARTICIPA_EN]-(e:Equipo)
RETURN s.id AS sede_id,
       s.nombre AS sede,
       count(DISTINCT e) AS equipos_conectados,
       count(DISTINCT p) AS partidos
ORDER BY equipos_conectados DESC, partidos DESC, sede_id
LIMIT 10;

// ============================================================ Visualizacion
// Ejecutar este bloque por separado en Neo4j Browser y elegir la vista Graph.
// Devuelve un subgrafo acotado de la final, legible para la evidencia (RF11).

MATCH camino=(e:Equipo)-[:PARTICIPA_EN]->(p:Partido {fase: 'Final'})
             -[:SE_DISPUTA_EN]->(s:Sede)
RETURN 'Visualizacion - subgrafo de la final' AS seccion, camino;
