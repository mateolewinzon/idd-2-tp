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

// Acelera las búsquedas cuando filtras por "Gol", "Tarjeta Roja", etc.
CREATE INDEX evento_tipo_idx IF NOT EXISTS
FOR (ev:Evento)
ON (ev.tipo);

// Acelera las consultas que agrupan o filtran por etapa del torneo
CREATE INDEX partido_fase_idx IF NOT EXISTS
FOR (p:Partido)
ON (p.fase);