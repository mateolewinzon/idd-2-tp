// ==============================================================================
// 05-operaciones-consultas.js - Operaciones 1 a 7 (Punto 4)
//
// Imprime cada operacion y sus documentos devueltos en formato JSON/BSON
// crudo (EJSON) sin parseo de bash, respetando los esquemas estrictos.
// ==============================================================================

const fixture = db.getSiblingDB("fixture2030");

// Helper para salida limpia de BSON/JSON
function imprimir(doc) {
  print(EJSON.stringify(doc, null, 2));
}

// -----------------------------------------------------------------------------
// 1. Insercion
// -----------------------------------------------------------------------------
print("================================================================================");
print("OPERACION 1: INSERCION");
print("Objetivo: Insertar un equipo y un jugador validando esquema $jsonSchema estricto.");
print("Condiciones: _id de 3 letras FIFA para equipo e Int32; _id compuesto para jugador");
print("             con dorsal Int32, fecha Date y snapshot desnormalizado de equipo.");
print("================================================================================");

fixture.equipos.deleteOne({ _id: "NZL" });
fixture.jugadores.deleteOne({ _id: "NZL-9" });

const nuevoEquipo = {
  _id: "NZL",
  nombre: "Nueva Zelanda",
  confederacion: "OFC",
  grupo: "P",
  ranking_fifa: NumberInt(85),
  participaciones_mundiales: NumberInt(3),
  director_tecnico: "Darren Bazeley",
  anfitrion: false,
};

const resEquipo = fixture.equipos.insertOne(nuevoEquipo);
print("\n--- Resultado de insercion en 'equipos' ---");
imprimir(resEquipo);
print("\n--- Documento insertado en 'equipos' ---");
imprimir(fixture.equipos.findOne({ _id: "NZL" }));

const nuevoJugador = {
  _id: "NZL-9",
  nombre: "Chris",
  apellido: "Wood",
  dorsal: NumberInt(9),
  posicion: "Delantero",
  pie_habil: "Derecho",
  fecha_nacimiento: ISODate("1991-12-07T00:00:00Z"),
  altura_cm: NumberInt(191),
  peso_kg: NumberInt(84),
  club: "Nottingham Forest",
  capitan: true,
  equipo: {
    _id: "NZL",
    nombre: "Nueva Zelanda",
    confederacion: "OFC",
  },
};

const resJugador = fixture.jugadores.insertOne(nuevoJugador);
print("\n--- Resultado de insercion en 'jugadores' ---");
imprimir(resJugador);
print("\n--- Documento insertado en 'jugadores' ---");
imprimir(fixture.jugadores.findOne({ _id: "NZL-9" }));


// -----------------------------------------------------------------------------
// 2. Recuperacion por identificador
// -----------------------------------------------------------------------------
print("\n================================================================================");
print("OPERACION 2: RECUPERACION POR IDENTIFICADOR");
print("Objetivo: Recuperacion en tiempo O(1) de una seleccion y un jugador por clave natural.");
print("Condiciones: _id == 'ARG' en equipos y _id == 'ARG-10' en jugadores.");
print("================================================================================");

print("\n--- Documento de equipo obtenido por _id: 'ARG' ---");
imprimir(fixture.equipos.findOne({ _id: "ARG" }));

print("\n--- Documento de jugador obtenido por _id: 'ARG-10' ---");
imprimir(fixture.jugadores.findOne({ _id: "ARG-10" }));


// -----------------------------------------------------------------------------
// 3. Recuperacion filtrada
// -----------------------------------------------------------------------------
print("\n================================================================================");
print("OPERACION 3: RECUPERACION FILTRADA");
print("Objetivo: Filtrar entidades aplicando condiciones de negocio compuestas.");
print("Condiciones: a) Equipos CONMEBOL con ranking_fifa <= 15 (cabezas de serie).");
print("             b) Delanteros UEFA con altura_cm >= 188 (porte fisico).");
print("================================================================================");

print("\n--- Equipos CONMEBOL en top 15 ranking FIFA ---");
imprimir(fixture.equipos.find({
  confederacion: "CONMEBOL",
  ranking_fifa: { $lte: 15 },
}).toArray());

print("\n--- Delanteros UEFA con altura >= 188 cm (muestra de 3 documentos) ---");
imprimir(fixture.jugadores.find({
  posicion: "Delantero",
  "equipo.confederacion": "UEFA",
  altura_cm: { $gte: 188 },
}).limit(3).toArray());


// -----------------------------------------------------------------------------
// 4. Proyeccion
// -----------------------------------------------------------------------------
print("\n================================================================================");
print("OPERACION 4: PROYECCION");
print("Objetivo: Reducir sobrecarga de red devolviendo solo campos para tarjetas de alineacion.");
print("Condiciones: Delanteros de 'ARG' proyectando dorsal, nombre, apellido, club y");
print("             equipo.nombre, excluyendo explicitamente _id (0).");
print("================================================================================");

print("\n--- Documentos proyectados (sin _id ni atributos fisicos no visibles) ---");
imprimir(fixture.jugadores.find(
  { "equipo._id": "ARG", posicion: "Delantero" },
  {
    _id: 0,
    dorsal: 1,
    apellido: 1,
    nombre: 1,
    club: 1,
    "equipo.nombre": 1,
  }
).toArray());


// -----------------------------------------------------------------------------
// 5. Ordenamiento y paginacion
// -----------------------------------------------------------------------------
print("\n================================================================================");
print("OPERACION 5: ORDENAMIENTO Y PAGINACION");
print("Objetivo: Paginacion determinista para interfaces graficas (UI) con gran volumen.");
print("Condiciones: Orden por { apellido: 1, nombre: 1 }, pagina 2 con tamanio 5");
print("             (skip: 5, limit: 5), servida mediante indice preexistente.");
print("================================================================================");

print("\n--- Documentos de la Pagina 2 del Directorio de Jugadores ---");
imprimir(fixture.jugadores
  .find({})
  .sort({ apellido: 1, nombre: 1 })
  .skip(5)
  .limit(5)
  .toArray()
);


// -----------------------------------------------------------------------------
// 6. Actualizacion
// -----------------------------------------------------------------------------
print("\n================================================================================");
print("OPERACION 6: ACTUALIZACION");
print("Objetivo: Actualizacion atomica preservando validador e integridad referencial.");
print("Condiciones: a) Equipos: $set en director_tecnico e $inc en participaciones_mundiales.");
print("             b) Jugadores: $set en club y peso_kg sin alterar subdocumento equipo.");
print("================================================================================");

const resUpdEquipo = fixture.equipos.updateOne(
  { _id: "ARG" },
  {
    $set: { director_tecnico: "Lionel Scaloni (Renovado)" },
    $inc: { participaciones_mundiales: NumberInt(1) },
  }
);
print("\n--- Resultado updateOne en 'equipos' ---");
imprimir(resUpdEquipo);
print("\n--- Documento de equipo luego del update ---");
imprimir(fixture.equipos.findOne({ _id: "ARG" }));

const resUpdJugador = fixture.jugadores.updateOne(
  { _id: "ARG-10" },
  {
    $set: {
      club: "Inter Miami CF",
      peso_kg: NumberInt(72),
    },
  }
);
print("\n--- Resultado updateOne en 'jugadores' ---");
imprimir(resUpdJugador);
print("\n--- Documento de jugador luego del update ---");
imprimir(fixture.jugadores.findOne({ _id: "ARG-10" }));


// -----------------------------------------------------------------------------
// 7. Agregacion
// -----------------------------------------------------------------------------
print("\n================================================================================");
print("OPERACION 7: AGREGACION");
print("Objetivo: Pipeline analitico consolidado cruzando ambas colecciones.");
print("Etapas: $match anfitriones -> $lookup con jugadores -> $unwind plantel ->");
print("        $group por seleccion y confederacion con $sum y $avg ->");
print("        $project con $round -> $sort por altura desc -> $limit 6.");
print("================================================================================");

const pipeline = [
  { $match: { anfitrion: true } },
  {
    $lookup: {
      from: "jugadores",
      localField: "_id",
      foreignField: "equipo._id",
      as: "plantel",
    },
  },
  { $unwind: "$plantel" },
  {
    $group: {
      _id: {
        codigo: "$_id",
        nombre: "$nombre",
        confederacion: "$confederacion",
      },
      total_convocados: { $sum: 1 },
      promedio_altura_cm: { $avg: "$plantel.altura_cm" },
      promedio_peso_kg: { $avg: "$plantel.peso_kg" },
    },
  },
  {
    $project: {
      _id: 0,
      codigo: "$_id.codigo",
      pais: "$_id.nombre",
      confederacion: "$_id.confederacion",
      total_convocados: 1,
      promedio_altura_cm: { $round: ["$promedio_altura_cm", 2] },
      promedio_peso_kg: { $round: ["$promedio_peso_kg", 2] },
    },
  },
  { $sort: { promedio_altura_cm: -1 } },
  { $limit: 6 },
];

print("\n--- Salida del pipeline de agregacion (BSON/JSON crudo) ---");
imprimir(fixture.equipos.aggregate(pipeline).toArray());
