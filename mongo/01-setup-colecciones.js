// Colecciones, reglas de validacion e indices.
//
// Idempotente: si la coleccion ya existe actualiza el validador con collMod en
// lugar de fallar al crearla.

// `db` es una global de mongosh; se usa otro nombre para no sombrearla.
const fixture = db.getSiblingDB("fixture2030");

const CONFEDERACIONES = ["UEFA", "CONMEBOL", "CAF", "AFC", "CONCACAF", "OFC"];
const POSICIONES = ["Arquero", "Defensor", "Mediocampista", "Delantero"];
const PIES = ["Derecho", "Izquierdo", "Ambidiestro"];

// validationAction "error" rechaza la escritura invalida en lugar de solo
// registrarla: es lo que convierte al esquema en garantia y no en advertencia.
// additionalProperties false cierra el documento, porque un atributo no previsto
// es casi siempre un error de tipeo en la carga.

const validadorEquipos = {
  $jsonSchema: {
    bsonType: "object",
    title: "Seleccion nacional participante del Fixture 2030",
    required: [
      "_id",
      "nombre",
      "confederacion",
      "grupo",
      "ranking_fifa",
      "participaciones_mundiales",
      "anfitrion",
    ],
    additionalProperties: false,
    properties: {
      _id: {
        bsonType: "string",
        pattern: "^[A-Z]{3}$",
        description: "Codigo FIFA de 3 letras mayusculas. Es el identificador natural.",
      },
      nombre: { bsonType: "string", minLength: 2, maxLength: 60 },
      confederacion: { enum: CONFEDERACIONES },
      grupo: {
        bsonType: "string",
        pattern: "^[A-P]$",
        description: "64 equipos en 16 grupos de 4.",
      },
      ranking_fifa: { bsonType: "int", minimum: 1, maximum: 250 },
      participaciones_mundiales: { bsonType: "int", minimum: 0, maximum: 30 },
      director_tecnico: { bsonType: "string", minLength: 3, maxLength: 80 },
      anfitrion: { bsonType: "bool" },
    },
  },
};

const validadorJugadores = {
  $jsonSchema: {
    bsonType: "object",
    title: "Jugador convocado por una seleccion del Fixture 2030",
    required: ["_id", "nombre", "apellido", "dorsal", "posicion", "fecha_nacimiento", "equipo"],
    additionalProperties: false,
    properties: {
      _id: {
        bsonType: "string",
        pattern: "^[A-Z]{3}-([1-9]|[1-9][0-9])$",
        description: "Codigo FIFA del equipo + dorsal. Ej: ARG-10.",
      },
      nombre: { bsonType: "string", minLength: 2, maxLength: 40 },
      apellido: { bsonType: "string", minLength: 2, maxLength: 40 },
      dorsal: {
        bsonType: "int",
        minimum: 1,
        maximum: 99,
        description: "Unico dentro del plantel, no globalmente (ver indice).",
      },
      posicion: { enum: POSICIONES },
      pie_habil: { enum: PIES },
      fecha_nacimiento: {
        bsonType: "date",
        description: "Date y no string, para poder ordenar y agregar por edad.",
      },
      altura_cm: { bsonType: "int", minimum: 150, maximum: 215 },
      peso_kg: { bsonType: "int", minimum: 50, maximum: 120 },
      club: { bsonType: "string", minLength: 2, maxLength: 60 },
      capitan: { bsonType: "bool" },

      // Referencia + desnormalizacion parcial: `equipo._id` apunta a equipos._id,
      // y nombre/confederacion son una copia de solo lectura que evita el $lookup
      // en la consulta dominante. Justificacion en el documento de decisiones.
      equipo: {
        bsonType: "object",
        required: ["_id", "nombre", "confederacion"],
        additionalProperties: false,
        properties: {
          _id: { bsonType: "string", pattern: "^[A-Z]{3}$" },
          nombre: { bsonType: "string", minLength: 2, maxLength: 60 },
          confederacion: { enum: CONFEDERACIONES },
        },
      },
    },
  },
};

function asegurarColeccion(nombre, validador) {
  const opciones = {
    validator: validador,
    validationLevel: "strict",
    validationAction: "error",
  };

  if (fixture.getCollectionNames().includes(nombre)) {
    fixture.runCommand({ collMod: nombre, ...opciones });
    print(`  [=] Coleccion "${nombre}" ya existia — validador actualizado con collMod.`);
  } else {
    fixture.createCollection(nombre, opciones);
    print(`  [+] Coleccion "${nombre}" creada con validador $jsonSchema.`);
  }
}

// Cada indice responde a una consulta concreta o a una restriccion de
// integridad. Los candidatos sin evidencia de explain() quedan fuera a
// proposito: el costo de escritura solo se justifica contra una consulta medida.
// _id ya viene indexado, asi que la recuperacion por identificador no suma nada.

const INDICES_EQUIPOS = [
  {
    clave: { nombre: 1 },
    opciones: { name: "idx_equipos_nombre_unico", unique: true },
    // Integridad (RNF3): impide dos selecciones con el mismo nombre.
  },
  {
    clave: { confederacion: 1, ranking_fifa: 1 },
    opciones: { name: "idx_equipos_confederacion_ranking" },
    // Filtra y ordena con el mismo indice, sin sort en memoria.
  },
  {
    clave: { grupo: 1 },
    opciones: { name: "idx_equipos_grupo" },
  },
];

const INDICES_JUGADORES = [
  {
    clave: { "equipo._id": 1, dorsal: 1 },
    opciones: { name: "idx_jugadores_equipo_dorsal_unico", unique: true },
    // Integridad (RNF3). Su prefijo sirve ademas la consulta mas frecuente del
    // modulo: el plantel completo de una seleccion.
  },
  {
    clave: { "equipo._id": 1, posicion: 1 },
    opciones: { name: "idx_jugadores_equipo_posicion" },
    // Plantel filtrado por puesto: alimenta la carga de una alineacion.
  },
  {
    clave: { apellido: 1, nombre: 1 },
    opciones: { name: "idx_jugadores_apellido_nombre" },
  },
];

function asegurarIndices(coleccion, definiciones) {
  definiciones.forEach((def) => {
    fixture.getCollection(coleccion).createIndex(def.clave, def.opciones);
    print(`  [i] ${coleccion}.${def.opciones.name}`);
  });
}

print("");
print("=== 01 — Setup de colecciones ===============================");
print("");
print("Base de datos: fixture2030");
print("");
print("Colecciones y validadores:");
asegurarColeccion("equipos", validadorEquipos);
asegurarColeccion("jugadores", validadorJugadores);

print("");
print("Indices:");
asegurarIndices("equipos", INDICES_EQUIPOS);
asegurarIndices("jugadores", INDICES_JUGADORES);

print("");
print("Setup completo.");
print("");
