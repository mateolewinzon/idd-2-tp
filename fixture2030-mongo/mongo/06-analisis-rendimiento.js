// ==============================================================================
// 06-analisis-rendimiento.js - Operacion 8 (Punto 5)
//
// Demuestra el ciclo formal de optimizacion sobre una consulta critica:
// 1. Diagnostico previo con explain("executionStats") sobre campo no indexado.
// 2. Creacion del indice con createIndex().
// 3. Medicion posterior con explain("executionStats") evidenciando la mejora.
// ==============================================================================

const fixture = db.getSiblingDB("fixture2030");

function imprimir(doc) {
  print(EJSON.stringify(doc, null, 2));
}

const CLUB_OBJETIVO = "Real Madrid";

// Limpieza inicial para garantizar estado antes del indice
try {
  fixture.jugadores.dropIndex("idx_jugadores_club_nacimiento");
} catch (e) {}

print("================================================================================");
print("PUNTO 5: ANALISIS DE RENDIMIENTO");
print("Consulta critica: Buscar jugadores por club ('Real Madrid') ordenados por fecha");
print("                  de nacimiento (fecha_nacimiento: 1).");
print("================================================================================");

print("\n--- PASO 1: explain('executionStats') ANTES de indexar (sin indice en club) ---");
const explainAntes = fixture.jugadores
  .find({ club: CLUB_OBJETIVO })
  .sort({ fecha_nacimiento: 1 })
  .explain("executionStats");

imprimir({
  queryPlanner: {
    winningPlan: explainAntes.queryPlanner.winningPlan,
  },
  executionStats: {
    executionSuccess: explainAntes.executionStats.executionSuccess,
    nReturned: explainAntes.executionStats.nReturned,
    executionTimeMillis: explainAntes.executionStats.executionTimeMillis,
    totalKeysExamined: explainAntes.executionStats.totalKeysExamined,
    totalDocsExamined: explainAntes.executionStats.totalDocsExamined,
  },
});

print("\n--- PASO 2: Creacion de indice compuesto optimizador con createIndex() ---");
const nombreIndice = fixture.jugadores.createIndex(
  { club: 1, fecha_nacimiento: 1 },
  { name: "idx_jugadores_club_nacimiento" }
);
print(`Indice creado: ${nombreIndice}`);

print("\n--- PASO 3: explain('executionStats') DESPUES de crear el indice ---");
const explainDespues = fixture.jugadores
  .find({ club: CLUB_OBJETIVO })
  .sort({ fecha_nacimiento: 1 })
  .explain("executionStats");

imprimir({
  queryPlanner: {
    winningPlan: explainDespues.queryPlanner.winningPlan,
  },
  executionStats: {
    executionSuccess: explainDespues.executionStats.executionSuccess,
    nReturned: explainDespues.executionStats.nReturned,
    executionTimeMillis: explainDespues.executionStats.executionTimeMillis,
    totalKeysExamined: explainDespues.executionStats.totalKeysExamined,
    totalDocsExamined: explainDespues.executionStats.totalDocsExamined,
  },
});
