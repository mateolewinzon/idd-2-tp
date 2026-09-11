// Conteos y controles de coherencia del grafo cargado (docs/modelo_grafo.md §5.2).
//
// scripts/cargar.sh lo ejecuta antes de cargar, despues de la primera carga y
// despues de repetirla: las dos ultimas salidas tienen que ser iguales (RNF4).

// ------------------------------------------------ Nodos por etiqueta
// Esperados: 64 equipos, 1.664 jugadores, 20 sedes, 127 partidos, 1.869 eventos.
MATCH (e:Equipo) RETURN count(e) AS equipos;
MATCH (j:Jugador) RETURN count(j) AS jugadores;
MATCH (s:Sede) RETURN count(s) AS sedes;
MATCH (p:Partido) RETURN count(p) AS partidos;
MATCH (ev:Evento) RETURN count(ev) AS eventos;

// ------------------------------------------------ Relaciones por tipo
// Esperadas: 1.664 PERTENECE_A, 127 SE_DISPUTA_EN, 254 PARTICIPA_EN,
// 3.826 ALINEADO_EN, 1.869 OCURRE_EN, 3.155 PROTAGONIZA.
MATCH ()-[r:PERTENECE_A]->() RETURN count(r) AS pertenece_a;
MATCH ()-[r:SE_DISPUTA_EN]->() RETURN count(r) AS se_disputa_en;
MATCH ()-[r:PARTICIPA_EN]->() RETURN count(r) AS participa_en;
MATCH ()-[r:ALINEADO_EN]->() RETURN count(r) AS alineado_en;
MATCH ()-[r:OCURRE_EN]->() RETURN count(r) AS ocurre_en;
MATCH ()-[r:PROTAGONIZA]->() RETURN count(r) AS protagoniza;

// ------------------------------------------------ Controles: todos deben dar 0
MATCH (j:Jugador) WHERE NOT (j)-[:PERTENECE_A]->(:Equipo) RETURN count(j) AS jugadores_sin_equipo;
MATCH (p:Partido) WHERE NOT (p)-[:SE_DISPUTA_EN]->(:Sede) RETURN count(p) AS partidos_sin_sede;
MATCH (p:Partido) WHERE NOT (:Equipo)-[:PARTICIPA_EN]->(p) RETURN count(p) AS partidos_sin_equipos;
MATCH (ev:Evento) WHERE NOT (ev)-[:OCURRE_EN]->(:Partido) RETURN count(ev) AS eventos_sin_partido;
MATCH (ev:Evento) WHERE NOT (:Jugador)-[:PROTAGONIZA]->(ev) RETURN count(ev) AS eventos_sin_protagonista;
