// CRUD basico sobre el modelo del Fixture 2030 (RF7).
//
// Se usan identificadores reservados con prefijo DEMO para no modificar los
// datos del torneo. El archivo es seguro de repetir: MERGE evita duplicados y el
// borrado final siempre esta filtrado por los dos id exactos.

// ============================================================ CREATE

MERGE (s:Sede {id: 'DEMO-SEDE'})
SET s.nombre = 'Estadio de prueba',
    s.ciudad = 'Ciudad de prueba',
    s.pais = 'Argentina';

MERGE (p:Partido {id: 'DEMO-PARTIDO'})
SET p.fase = 'Amistoso',
    p.fecha = date('2030-05-01');

MATCH (p:Partido {id: 'DEMO-PARTIDO'}), (s:Sede {id: 'DEMO-SEDE'})
MERGE (p)-[:SE_DISPUTA_EN]->(s);

// ============================================================ READ

MATCH (p:Partido {id: 'DEMO-PARTIDO'})-[r:SE_DISPUTA_EN]->(s:Sede {id: 'DEMO-SEDE'})
RETURN p.id AS partido, p.fase AS fase, type(r) AS relacion,
       s.id AS sede, s.nombre AS nombre_sede;

// ============================================================ UPDATE

MATCH (s:Sede {id: 'DEMO-SEDE'})
SET s.nombre = 'Estadio de prueba actualizado'
RETURN s.id AS sede, s.nombre AS nombre_actualizado;

// ============================================================ DELETE DE RELACION

MATCH (:Partido {id: 'DEMO-PARTIDO'})-[r:SE_DISPUTA_EN]->(:Sede {id: 'DEMO-SEDE'})
DELETE r;

MATCH (:Partido {id: 'DEMO-PARTIDO'})-[r:SE_DISPUTA_EN]->(:Sede {id: 'DEMO-SEDE'})
RETURN count(r) AS relaciones_demo_restantes;

// ============================================================ DELETE DE NODOS

// DETACH DELETE permite limpiar aun si una corrida anterior quedo incompleta.
// El filtro por id exacto evita el borrado accidental de datos reales.
MATCH (n)
WHERE n.id IN ['DEMO-PARTIDO', 'DEMO-SEDE']
DETACH DELETE n;

MATCH (n)
WHERE n.id IN ['DEMO-PARTIDO', 'DEMO-SEDE']
RETURN count(n) AS nodos_demo_restantes;
