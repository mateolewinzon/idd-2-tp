// Carga de 1.664 jugadores: 26 por seleccion x 64 selecciones.
//
// 26 es el tamano de plantel que la FIFA habilita hoy, y 1.664 supera tanto el
// minimo de 1.000 de RF5 como el "mas de 1.500" del escenario del Hito 4 (con 23
// por plantel darian 1.472 y quedariamos por debajo de esa segunda cifra).
//
// Los datos son sinteticos pero NO aleatorios: el generador se siembra con un
// hash del codigo FIFA, asi que produce siempre los mismos documentos. Sin eso
// la carga no seria reproducible — cada corrida generaria personas distintas y
// el upsert modificaria los 1.664 documentos en lugar de no hacer nada.

const fixture = db.getSiblingDB("fixture2030");

const REFERENCIA = { anio: 2030 };
const JUGADORES_POR_EQUIPO = 26;

const COMPOSICION = [
  { posicion: "Arquero", cantidad: 3 },
  { posicion: "Defensor", cantidad: 8 },
  { posicion: "Mediocampista", cantidad: 9 },
  { posicion: "Delantero", cantidad: 6 },
];

const FISICO = {
  Arquero: { altura: [185, 200], peso: [78, 95] },
  Defensor: { altura: [178, 195], peso: [72, 90] },
  Mediocampista: { altura: [168, 186], peso: [64, 80] },
  Delantero: { altura: [172, 192], peso: [68, 86] },
};

const NOMBRES = {
  UEFA: ["Lucas","Mateo","Nicolas","Thomas","Julian","Marco","Andreas","Stefan","Pavel","Kristian","Daniel","Antoine","Leon","Robin","Viktor","Emil","Jonas","Milan","Rafael","Sergio"],
  CONMEBOL: ["Santiago","Facundo","Matias","Joaquin","Bruno","Rodrigo","Emiliano","Thiago","Agustin","Nahuel","Gonzalo","Ignacio","Franco","Alvaro","Ezequiel","Diego","Camilo","Julio","Renato","Maximiliano"],
  CAF: ["Amadou","Youssef","Kwame","Ibrahim","Sekou","Tarek","Kofi","Mamadou","Hicham","Chiedozie","Bakary","Ayoub","Tendai","Rachid","Oumar","Sipho","Idrissa","Nabil","Cheikh","Zola"],
  AFC: ["Haruki","Minjun","Ali","Reza","Kenta","Jihoon","Omar","Yusuf","Takumi","Seojun","Faisal","Hassan","Sora","Dongwon","Karim","Ahmad","Riku","Jinwoo","Bilal","Nasser"],
  CONCACAF: ["Carlos","Andres","Kevin","Jean","Luis","Marlon","Alexis","Roberto","Wilfried","Jorge","Bryan","Damian","Eduardo","Nelson","Osvaldo","Ricardo","Pierre","Anthony","Manuel","Hector"],
  OFC: ["Tama","Liam","Noa","Jayden","Kalani","Ethan","Tevita","Manu","Ari","Rewi","Caleb","Sione","Malu","Ryder","Hemi","Josua","Taine","Kalolo","Dylan","Aleki"],
};

const APELLIDOS = {
  UEFA: ["Novak","Muller","Bakker","Larsson","Kovacs","Bianchi","Moreau","Silva","Nowak","Petrov","Andersen","Fischer","Hansen","Marino","Weber","Duarte","Kaminski","Rossi","Vidal","Horvat"],
  CONMEBOL: ["Gimenez","Ferreira","Quiroga","Bermudez","Ocampo","Villalba","Sandoval","Castillo","Meireles","Zambrano","Escobar","Paredes","Cardozo","Aguilera","Bustos","Maldonado","Rojas","Peralta","Barrios","Cabrera"],
  CAF: ["Traore","Diallo","Mensah","Boateng","Cisse","Benali","Osei","Keita","Ndiaye","Bekele","Adeyemi","Toure","Mokoena","Zerhouni","Camara","Nkemelu","Sylla","Haddad","Bamba","Dube"],
  AFC: ["Tanaka","Kim","Rahimi","Nakamura","Park","Al Harbi","Yamamoto","Choi","Karimov","Saito","Al Mansouri","Lee","Hosseini","Watanabe","Jang","Abbas","Ito","Shin","Farhadi","Aziz"],
  CONCACAF: ["Hernandez","Campbell","Lafleur","Vargas","Solano","Baptiste","Guzman","Ramirez","Charles","Delgado","Espinoza","Pierre","Navarro","Serrano","Ortega","Mendoza","Jean-Louis","Salazar","Coronado","Reyes"],
  OFC: ["Waititi","Thompson","Kaimana","Tupou","Ngata","Fifita","Halapua","Morrison","Tuilagi","Rakau","Vaega","Latu","Hokianga","Sione","Naidu","Mataitini","Kamoto","Paulo","Ravu","Tamati"],
};

const CLUBES = [
  "Real Madrid","FC Barcelona","Atletico de Madrid","Sevilla FC","Manchester City","Liverpool","Arsenal","Chelsea","Tottenham Hotspur","Newcastle United","Aston Villa","Bayern Munich","Borussia Dortmund","Bayer Leverkusen","RB Leipzig","Eintracht Frankfurt","Paris Saint-Germain","Olympique de Marsella","Olympique de Lyon","AS Monaco","Inter de Milan","AC Milan","Juventus","Napoli","AS Roma","Benfica","Sporting CP","Porto","Ajax","PSV Eindhoven","Feyenoord","Galatasaray","Fenerbahce","Boca Juniors","River Plate","Flamengo","Palmeiras","Club America","LA Galaxy","Inter Miami","Al Hilal","Al Nassr","Urawa Red Diamonds","Ulsan HD",
];

const PIES = ["Derecho", "Izquierdo", "Ambidiestro"];

// FNV-1a de 32 bits: convierte "ARG" en una semilla estable.
function hashSemilla(texto) {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < texto.length; i++) {
    h ^= texto.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h >>> 0;
}

// mulberry32: misma semilla, misma secuencia, siempre.
function mulberry32(semilla) {
  let a = semilla >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function generarPlantel(equipo) {
  const rnd = mulberry32(hashSemilla(equipo._id));
  const entero = (min, max) => min + Math.floor(rnd() * (max - min + 1));
  const elegir = (arr) => arr[Math.floor(rnd() * arr.length)];

  const nombres = NOMBRES[equipo.confederacion];
  const apellidos = APELLIDOS[equipo.confederacion];

  const DORSALES_ARQUERO = [1, 12, 23];
  const dorsalesCampo = [];
  for (let n = 1; n <= JUGADORES_POR_EQUIPO; n++) {
    if (!DORSALES_ARQUERO.includes(n)) dorsalesCampo.push(n);
  }

  const usados = new Set(); // evita dos "Lucas Novak" en el mismo plantel
  const plantel = [];
  let siguienteArquero = 0;
  let siguienteCampo = 0;

  COMPOSICION.forEach(({ posicion, cantidad }) => {
    for (let i = 0; i < cantidad; i++) {
      let nombre;
      let apellido;
      let intentos = 0;
      do {
        nombre = elegir(nombres);
        apellido = elegir(apellidos);
        intentos++;
      } while (usados.has(`${nombre} ${apellido}`) && intentos < 50);
      usados.add(`${nombre} ${apellido}`);

      const dorsal =
        posicion === "Arquero"
          ? DORSALES_ARQUERO[siguienteArquero++]
          : dorsalesCampo[siguienteCampo++];

      const edad = entero(18, 38);
      const fisico = FISICO[posicion];

      const p = rnd();
      const pie = p < 0.7 ? PIES[0] : p < 0.95 ? PIES[1] : PIES[2];

      plantel.push({
        _id: `${equipo._id}-${dorsal}`,
        nombre: nombre,
        apellido: apellido,
        dorsal: Int32(dorsal),
        posicion: posicion,
        pie_habil: pie,
        fecha_nacimiento: new Date(
          Date.UTC(REFERENCIA.anio - edad, entero(0, 11), entero(1, 28)),
        ),
        altura_cm: Int32(entero(fisico.altura[0], fisico.altura[1])),
        peso_kg: Int32(entero(fisico.peso[0], fisico.peso[1])),
        club: elegir(CLUBES),
        capitan: dorsal === 10,
        equipo: {
          _id: equipo._id,
          nombre: equipo.nombre,
          confederacion: equipo.confederacion,
        },
      });
    }
  });

  return plantel;
}

print("");
print("=== 03 — Carga de jugadores =================================");
print("");

// Los jugadores se generan a partir de los equipos YA PERSISTIDOS, no del
// archivo de datos: asi es imposible producir un jugador cuyo equipo no exista y
// el snapshot desnormalizado sale siempre de la fuente de verdad. La relacion
// queda garantizada por construccion, no por una verificacion posterior.
const equipos = fixture.equipos.find({}).sort({ _id: 1 }).toArray();

if (equipos.length === 0) {
  print("  ERROR: no hay equipos cargados. Ejecutar antes 02-carga-equipos.js.");
  print("");
  quit(1);
}

print(`Equipos leidos desde la base: ${equipos.length}`);

const operaciones = [];
equipos.forEach((equipo) => {
  generarPlantel(equipo).forEach((jugador) => {
    const { _id, ...campos } = jugador;
    operaciones.push({
      updateOne: {
        filter: { _id: _id },
        update: { $set: campos },
        upsert: true,
      },
    });
  });
});

print(`Documentos generados: ${operaciones.length} (${JUGADORES_POR_EQUIPO} por equipo)`);

const resultado = fixture.jugadores.bulkWrite(operaciones, { ordered: false });

print("");
print("Resultado del bulkWrite (upsert por <codigo FIFA>-<dorsal>):");
print(`  Documentos encontrados (matched):  ${resultado.matchedCount}`);
print(`  Documentos insertados (upserted):  ${resultado.upsertedCount}`);
print(`  Documentos modificados (modified): ${resultado.modifiedCount}`);

if (resultado.upsertedCount === 0 && resultado.modifiedCount === 0) {
  print("");
  print("  -> Sin cambios: la base ya estaba en el estado esperado.");
  print("     Esta es la evidencia de idempotencia que pide RF8.");
}

const total = fixture.jugadores.countDocuments();
print("");
print(`Total de jugadores en la coleccion: ${total}`);
if (total < 1000) {
  print(`  ADVERTENCIA: RF5 exige al menos 1.000 y hay ${total}.`);
}

print("");
print("Reparto por posicion:");
fixture.jugadores
  .aggregate([
    { $group: { _id: "$posicion", jugadores: { $sum: 1 } } },
    { $sort: { jugadores: -1 } },
  ])
  .forEach((r) => print(`  ${r._id.padEnd(15)} ${String(r.jugadores).padStart(4)}`));

print("");
