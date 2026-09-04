// Verificacion de volumen (RNF2) e integridad documental (RNF3).
// Solo lectura. Termina con codigo distinto de cero si algo falla.

const fixture = db.getSiblingDB("fixture2030");

let fallidas = 0;

function verificar(titulo, condicion, detalle) {
  const marca = condicion ? "OK  " : "FALLA";
  if (!condicion) fallidas++;
  print(`  [${marca}] ${titulo}`);
  if (detalle) print(`          ${detalle}`);
}

print("");
print("=== 04 — Verificacion de integridad =========================");
print("");
print("RNF2 — Volumen minimo");

const totalEquipos = fixture.equipos.countDocuments();
verificar("64 equipos persistidos (RF4)", totalEquipos === 64, `encontrados: ${totalEquipos}`);

const totalJugadores = fixture.jugadores.countDocuments();
verificar(
  "Al menos 1.000 jugadores persistidos (RF5)",
  totalJugadores >= 1000,
  `encontrados: ${totalJugadores}`,
);

verificar(
  "Mas de 1.500 jugadores, segun la cifra del escenario del Hito 4",
  totalJugadores > 1500,
  `encontrados: ${totalJugadores}`,
);

print("");
print("RNF3 — Identificadores sin duplicados");

// _id es unico por definicion; lo que puede duplicarse es un identificador de
// negocio que no sea _id. Se verifican los dos casos reales.
const nombresDuplicados = fixture.equipos
  .aggregate([
    { $group: { _id: "$nombre", n: { $sum: 1 } } },
    { $match: { n: { $gt: 1 } } },
  ])
  .toArray();
verificar(
  "Ningun nombre de seleccion repetido",
  nombresDuplicados.length === 0,
  nombresDuplicados.length === 0
    ? "protegido por idx_equipos_nombre_unico"
    : `repetidos: ${nombresDuplicados.map((d) => d._id).join(", ")}`,
);

const dorsalesDuplicados = fixture.jugadores
  .aggregate([
    { $group: { _id: { equipo: "$equipo._id", dorsal: "$dorsal" }, n: { $sum: 1 } } },
    { $match: { n: { $gt: 1 } } },
  ])
  .toArray();
verificar(
  "Ningun dorsal repetido dentro de un mismo plantel",
  dorsalesDuplicados.length === 0,
  dorsalesDuplicados.length === 0
    ? "protegido por idx_jugadores_equipo_dorsal_unico"
    : `${dorsalesDuplicados.length} colisiones`,
);

print("");
print("RNF3 — Relacion equipo-jugador valida en el 100% de los casos");

const idsEquipos = fixture.equipos.distinct("_id");
const huerfanos = fixture.jugadores.countDocuments({ "equipo._id": { $nin: idsEquipos } });
verificar(
  "Ningun jugador huerfano (equipo._id inexistente)",
  huerfanos === 0,
  `jugadores con referencia rota: ${huerfanos}`,
);

const sinPlantel = fixture.equipos
  .aggregate([
    {
      $lookup: {
        from: "jugadores",
        localField: "_id",
        foreignField: "equipo._id",
        as: "plantel",
      },
    },
    { $match: { $expr: { $lt: [{ $size: "$plantel" }, 1] } } },
    { $project: { _id: 1 } },
  ])
  .toArray();
verificar(
  "Ningun equipo sin jugadores",
  sinPlantel.length === 0,
  sinPlantel.length === 0 ? "" : `sin plantel: ${sinPlantel.map((e) => e._id).join(", ")}`,
);

// Audita el costo aceptado al desnormalizar: si el snapshot embebido en el
// jugador se desfasa del documento del equipo, la lectura sin $lookup empieza a
// devolver informacion vieja. Que hoy de cero es lo que sostiene esa decision.
const desincronizados = fixture.jugadores
  .aggregate([
    {
      $lookup: {
        from: "equipos",
        localField: "equipo._id",
        foreignField: "_id",
        as: "fuente",
      },
    },
    { $unwind: "$fuente" },
    {
      $match: {
        $expr: {
          $or: [
            { $ne: ["$equipo.nombre", "$fuente.nombre"] },
            { $ne: ["$equipo.confederacion", "$fuente.confederacion"] },
          ],
        },
      },
    },
    { $count: "total" },
  ])
  .toArray();
const totalDesinc = desincronizados.length > 0 ? desincronizados[0].total : 0;
verificar(
  "Snapshot desnormalizado sincronizado con el documento del equipo",
  totalDesinc === 0,
  `jugadores con snapshot desfasado: ${totalDesinc}`,
);

print("");
print("RNF3 — Campos criticos presentes");

const equiposIncompletos = fixture.equipos.countDocuments({
  $or: [
    { nombre: { $in: [null, ""] } },
    { confederacion: null },
    { grupo: null },
    { ranking_fifa: null },
  ],
});
verificar(
  "Ningun equipo con campos criticos ausentes",
  equiposIncompletos === 0,
  `equipos incompletos: ${equiposIncompletos}`,
);

const jugadoresIncompletos = fixture.jugadores.countDocuments({
  $or: [
    { nombre: { $in: [null, ""] } },
    { apellido: { $in: [null, ""] } },
    { dorsal: null },
    { posicion: null },
    { fecha_nacimiento: null },
    { "equipo._id": null },
  ],
});
verificar(
  "Ningun jugador con campos criticos ausentes",
  jugadoresIncompletos === 0,
  `jugadores incompletos: ${jugadoresIncompletos}`,
);

print("");
print("Coherencia de los planteles");

const plantelesIrregulares = fixture.jugadores
  .aggregate([
    {
      $group: {
        _id: "$equipo._id",
        n: { $sum: 1 },
        capitanes: { $sum: { $cond: ["$capitan", 1, 0] } },
      },
    },
    { $match: { $or: [{ n: { $ne: 26 } }, { capitanes: { $ne: 1 } }] } },
  ])
  .toArray();
verificar(
  "Todos los planteles tienen 26 jugadores y exactamente 1 capitan",
  plantelesIrregulares.length === 0,
  plantelesIrregulares.length === 0
    ? ""
    : plantelesIrregulares.map((p) => `${p._id}: ${p.n} jug., ${p.capitanes} cap.`).join(" | "),
);

print("");
print("Configuracion de las colecciones");

["equipos", "jugadores"].forEach((nombre) => {
  const info = fixture.getCollectionInfos({ name: nombre })[0];
  const tieneValidador = !!(info && info.options && info.options.validator);
  const accion = info && info.options ? info.options.validationAction : "—";
  verificar(
    `Coleccion "${nombre}" con validador $jsonSchema activo`,
    tieneValidador && accion === "error",
    `validationAction: ${accion}`,
  );
});

["equipos", "jugadores"].forEach((nombre) => {
  const indices = fixture
    .getCollection(nombre)
    .getIndexes()
    .map((i) => i.name);
  print(`  [info ] Indices en "${nombre}": ${indices.join(", ")}`);
});

print("");
print("-------------------------------------------------------------");
if (fallidas === 0) {
  print(`  RESULTADO: todas las verificaciones pasaron.`);
  print(`  ${totalEquipos} equipos | ${totalJugadores} jugadores | 0 huerfanos`);
  print("-------------------------------------------------------------");
  print("");
} else {
  print(`  RESULTADO: ${fallidas} verificacion(es) fallaron.`);
  print("-------------------------------------------------------------");
  print("");
  quit(1);
}
