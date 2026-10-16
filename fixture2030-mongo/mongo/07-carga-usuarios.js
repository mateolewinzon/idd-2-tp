// Carga de los usuarios de muestra.
//
// Idempotente por upsert sobre _id, igual que equipos:
//   Primera corrida:   upserted = 6, modified = 0
//   Corridas sucesivas: upserted = 0, modified = 0

const fixture = db.getSiblingDB("fixture2030");

load("/datos/usuarios.js");
const USUARIOS = globalThis.USUARIOS;

function abortar(mensaje) {
  print("");
  print(`  ERROR: ${mensaje}`);
  print("  No se escribio ningun documento.");
  print("");
  quit(1);
}

// $jsonSchema valida cada documento por separado; la repeticion dentro del
// dataset se detecta aca, antes de escribir.
if (new Set(USUARIOS.map((u) => u._id)).size !== USUARIOS.length) {
  abortar("hay _id de usuario repetidos en el dataset.");
}
if (new Set(USUARIOS.map((u) => u.email)).size !== USUARIOS.length) {
  abortar("hay emails repetidos en el dataset.");
}

const operaciones = USUARIOS.map((usuario) => {
  const { _id, ...campos } = usuario;
  return { updateOne: { filter: { _id }, update: { $set: campos }, upsert: true } };
});

print("");
print("=== 07 — Carga de usuarios ==================================");
print("");
print(`Dataset validado: ${USUARIOS.length} usuarios.`);

const resultado = fixture.usuarios.bulkWrite(operaciones, { ordered: false });

print("");
print("Resultado del bulkWrite (upsert por _id):");
print(`  Documentos encontrados (matched):  ${resultado.matchedCount}`);
print(`  Documentos insertados (upserted):  ${resultado.upsertedCount}`);
print(`  Documentos modificados (modified): ${resultado.modifiedCount}`);

if (resultado.upsertedCount === 0 && resultado.modifiedCount === 0) {
  print("");
  print("  -> Sin cambios: la base ya estaba en el estado esperado.");
}

print("");
print(`Total de usuarios en la coleccion: ${fixture.usuarios.countDocuments()}`);
print("");
