// Carga de los 64 equipos.
//
// Idempotente por upsert sobre _id (el codigo FIFA), sin deleteMany previo:
//   Primera corrida:   upserted = 64, modified = 0
//   Corridas sucesivas: upserted = 0, modified = 0

const fixture = db.getSiblingDB("fixture2030");

load("/datos/equipos.js");
const EQUIPOS = globalThis.EQUIPOS;

function abortar(mensaje) {
  print("");
  print(`  ERROR: ${mensaje}`);
  print("  No se escribio ningun documento.");
  print("");
  quit(1);
}

// $jsonSchema controla cada documento por separado y no puede ver el conjunto:
// no sabe que tienen que ser 64 ni que los codigos no se repiten. Eso va aca, y
// aborta antes de escribir nada.
if (EQUIPOS.length !== 64) {
  abortar(`el dataset tiene ${EQUIPOS.length} equipos y el escenario exige 64 (RF4).`);
}

const codigos = new Set(EQUIPOS.map((e) => e._id));
if (codigos.size !== 64) {
  abortar("hay codigos FIFA repetidos en el dataset.");
}

const nombres = new Set(EQUIPOS.map((e) => e.nombre));
if (nombres.size !== 64) {
  abortar("hay nombres de seleccion repetidos en el dataset.");
}

const porGrupo = {};
EQUIPOS.forEach((e) => {
  porGrupo[e.grupo] = (porGrupo[e.grupo] || 0) + 1;
});
const gruposInvalidos = Object.keys(porGrupo).filter((g) => porGrupo[g] !== 4);
if (gruposInvalidos.length > 0) {
  abortar(`los grupos ${gruposInvalidos.join(", ")} no tienen exactamente 4 equipos.`);
}

// Int32() es obligatorio: mongosh serializa los numeros como double y el
// validador, que exige bsonType "int", rechazaria el documento.
const operaciones = EQUIPOS.map((equipo) => ({
  updateOne: {
    filter: { _id: equipo._id },
    update: {
      $set: {
        nombre: equipo.nombre,
        confederacion: equipo.confederacion,
        grupo: equipo.grupo,
        ranking_fifa: Int32(equipo.ranking_fifa),
        participaciones_mundiales: Int32(equipo.participaciones_mundiales),
        director_tecnico: equipo.director_tecnico,
        anfitrion: equipo.anfitrion,
      },
    },
    upsert: true,
  },
}));

print("");
print("=== 02 — Carga de equipos ===================================");
print("");
print(`Dataset validado: ${EQUIPOS.length} equipos, 16 grupos de 4.`);

const resultado = fixture.equipos.bulkWrite(operaciones, { ordered: false });

print("");
print("Resultado del bulkWrite (upsert por codigo FIFA):");
print(`  Documentos encontrados (matched):  ${resultado.matchedCount}`);
print(`  Documentos insertados (upserted):  ${resultado.upsertedCount}`);
print(`  Documentos modificados (modified): ${resultado.modifiedCount}`);

if (resultado.upsertedCount === 0 && resultado.modifiedCount === 0) {
  print("");
  print("  -> Sin cambios: la base ya estaba en el estado esperado.");
  print("     Esta es la evidencia de idempotencia que pide RF8.");
}

const total = fixture.equipos.countDocuments();
print("");
print(`Total de equipos en la coleccion: ${total}`);
if (total !== 64) {
  print(`  ADVERTENCIA: se esperaban 64 y hay ${total}. Revisar 04-verificar-integridad.js.`);
}

print("");
print("Reparto por confederacion:");
fixture.equipos
  .aggregate([
    { $group: { _id: "$confederacion", equipos: { $sum: 1 } } },
    { $sort: { equipos: -1, _id: 1 } },
  ])
  .forEach((r) => print(`  ${r._id.padEnd(10)} ${String(r.equipos).padStart(2)}`));

print("");
