// Garantizar unicidad en los nodos provenientes de Hito 4
CREATE CONSTRAINT equipo_id_unique IF NOT EXISTS
FOR (e:Equipo)
REQUIRE e.id IS UNIQUE;
CREATE CONSTRAINT jugador_id_unique IF NOT EXISTS
FOR (j:Jugador)
REQUIRE j.id IS UNIQUE;

// Garantizar unicidad en los nodos exclusivos de Hito 5
CREATE CONSTRAINT partido_id_unique IF NOT EXISTS
FOR (p:Partido)
REQUIRE p.id IS UNIQUE;
CREATE CONSTRAINT sede_id_unique IF NOT EXISTS
FOR (s:Sede)
REQUIRE s.id IS UNIQUE;
CREATE CONSTRAINT evento_id_unique IF NOT EXISTS
FOR (ev:Evento)
REQUIRE ev.id IS UNIQUE;

// CREATE INDEX: encontrado en documentación Neo4j Docs (Cypher Manual, sección Indexes).
// En clase solo se vio CREATE CONSTRAINT; la justificación de cada índice está en
// docs/modelo_grafo.md §5.3.

// Para las consultas que filtran eventos por tipo ("Gol", "Tarjeta Roja", etc.; preguntas 1 a 4 de docs/modelo_grafo.md)
CREATE INDEX evento_tipo_idx IF NOT EXISTS
FOR (ev:Evento)
ON (ev.tipo);

// Para las consultas que filtran por etapa del torneo (pregunta 5 de docs/modelo_grafo.md)
CREATE INDEX partido_fase_idx IF NOT EXISTS
FOR (p:Partido)
ON (p.fase);