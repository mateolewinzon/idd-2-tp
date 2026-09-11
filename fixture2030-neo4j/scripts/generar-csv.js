// Generador de los CSV de import/ que lee queries/carga.cypher (Hito 5).
//
// Se ejecuta con mongosh dentro del contenedor de MongoDB del Hito 4, a traves de
// scripts/generar-csv.sh. Corre ahi por dos motivos:
//   1. equipos.csv y jugadores.csv salen de las colecciones reales: los id del
//      grafo son exactamente los _id de MongoDB (RF5).
//   2. Partidos, alineaciones y eventos se generan a partir de esos mismos
//      equipos y jugadores: no puede aparecer un equipo o jugador inexistente.
//
// Los datos son sinteticos pero NO aleatorios, con la misma tecnica que
// 03-carga-jugadores.js del Hito 4: cada partido siembra su generador con un hash
// de su id, asi que la misma base produce siempre los mismos CSV.
//
// Cada corrida imprime un solo archivo, el que indica la variable ARCHIVO (que
// generar-csv.sh define antes de este codigo), o la cantidad de filas de cada
// archivo si ARCHIVO es "resumen".

const fixture = db.getSiblingDB("fixture2030");

// Igual que en 02-carga-equipos.js: imprime el motivo y termina con codigo 1, asi
// generar-csv.sh no reemplaza el CSV anterior.
function abortar(mensaje) {
  print(`ERROR: ${mensaje}`);
  quit(1);
}

function verificar(condicion, mensaje) {
  if (!condicion) abortar(`control de coherencia: ${mensaje}`);
}

// --- Generador determinista (igual que en 03-carga-jugadores.js) -------------

// FNV-1a de 32 bits: convierte un texto ("P-001") en una semilla estable.
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

function crearAzar(texto) {
  const rnd = mulberry32(hashSemilla(texto));
  const entero = (min, max) => min + Math.floor(rnd() * (max - min + 1));
  // Elige un elemento de la lista con probabilidad proporcional a su peso.
  const ponderado = (lista, peso) => {
    let total = 0;
    lista.forEach((x) => (total += peso(x)));
    let r = rnd() * total;
    for (let i = 0; i < lista.length; i++) {
      r -= peso(lista[i]);
      if (r < 0) return lista[i];
    }
    return lista[lista.length - 1];
  };
  return { rnd, entero, ponderado };
}

// --- Sedes: 20 estadios de los seis paises anfitriones ------------------------

const SEDES = [
  { id: "S-01", nombre: "Estadio Centenario",               ciudad: "Montevideo",    pais: "Uruguay" },
  { id: "S-02", nombre: "Estadio Monumental",               ciudad: "Buenos Aires",  pais: "Argentina" },
  { id: "S-03", nombre: "Estadio Defensores del Chaco",     ciudad: "Asuncion",      pais: "Paraguay" },
  { id: "S-04", nombre: "Estadio Santiago Bernabeu",        ciudad: "Madrid",        pais: "Espana" },
  { id: "S-05", nombre: "Estadio Metropolitano",            ciudad: "Madrid",        pais: "Espana" },
  { id: "S-06", nombre: "Estadio Camp Nou",                 ciudad: "Barcelona",     pais: "Espana" },
  { id: "S-07", nombre: "Estadio La Cartuja",               ciudad: "Sevilla",       pais: "Espana" },
  { id: "S-08", nombre: "Estadio San Mames",                ciudad: "Bilbao",        pais: "Espana" },
  { id: "S-09", nombre: "Estadio Anoeta",                   ciudad: "San Sebastian", pais: "Espana" },
  { id: "S-10", nombre: "Estadio Riazor",                   ciudad: "A Coruna",      pais: "Espana" },
  { id: "S-11", nombre: "Estadio de Gran Canaria",          ciudad: "Las Palmas",    pais: "Espana" },
  { id: "S-12", nombre: "Estadio da Luz",                   ciudad: "Lisboa",        pais: "Portugal" },
  { id: "S-13", nombre: "Estadio Jose Alvalade",            ciudad: "Lisboa",        pais: "Portugal" },
  { id: "S-14", nombre: "Estadio do Dragao",                ciudad: "Porto",         pais: "Portugal" },
  { id: "S-15", nombre: "Gran Estadio Hassan II",           ciudad: "Casablanca",    pais: "Marruecos" },
  { id: "S-16", nombre: "Estadio Principe Moulay Abdellah", ciudad: "Rabat",         pais: "Marruecos" },
  { id: "S-17", nombre: "Estadio Ibn Batouta",              ciudad: "Tanger",        pais: "Marruecos" },
  { id: "S-18", nombre: "Gran Estadio de Marrakech",        ciudad: "Marrakech",     pais: "Marruecos" },
  { id: "S-19", nombre: "Gran Estadio de Agadir",           ciudad: "Agadir",        pais: "Marruecos" },
  { id: "S-20", nombre: "Gran Estadio de Fez",              ciudad: "Fez",           pais: "Marruecos" },
];

// Los tres anfitriones sudamericanos juegan en casa su primer partido de grupo
// (los "partidos del centenario" de equipos.js). El resto del torneo se juega en
// Espana, Portugal y Marruecos.
const CENTENARIO = [
  { equipo: "URU", sede: "S-01", dia: 8 },
  { equipo: "ARG", sede: "S-02", dia: 9 },
  { equipo: "PAR", sede: "S-03", dia: 10 },
];

const SEDES_EUROPA_AFRICA = [
  "S-04", "S-05", "S-06", "S-07", "S-08", "S-09", "S-10", "S-11", "S-12",
  "S-13", "S-14", "S-15", "S-16", "S-17", "S-18", "S-19", "S-20",
];

// Eliminacion directa: las rondas finales se concentran en menos estadios.
const SEDES_ELIMINACION = {
  Dieciseisavos: [
    "S-05", "S-06", "S-07", "S-08", "S-09", "S-10", "S-11", "S-12",
    "S-13", "S-14", "S-15", "S-16", "S-17", "S-18", "S-19", "S-20",
  ],
  Octavos: ["S-04", "S-06", "S-15", "S-12", "S-05", "S-16", "S-14", "S-18"],
  Cuartos: ["S-04", "S-06", "S-15", "S-12"],
  Semifinal: ["S-06", "S-15"],
  Final: ["S-04"],
};

// --- Calendario -----------------------------------------------------------------

// Cada fecha se maneja como dia del torneo contado desde el 1 de junio de 2030
// (dia 1 = 1 de junio, dia 31 = 1 de julio).
function fecha(dia) {
  const mes = dia <= 30 ? "06" : "07";
  const diaDelMes = dia <= 30 ? dia : dia - 30;
  return `2030-${mes}-${String(diaDelMes).padStart(2, "0")}`;
}

// Fase de grupos: jornada 1 del 11 al 14 de junio, jornada 2 del 16 al 19 y
// jornada 3 del 21 al 24; cuatro grupos por dia.
function diaDeGrupo(jornada, indiceGrupo) {
  return 11 + jornada * 5 + Math.floor(indiceGrupo / 4);
}

const RONDAS = [
  { fase: "Dieciseisavos", primerDia: 27, porDia: 4 }, // 27 al 30 de junio
  { fase: "Octavos",       primerDia: 33, porDia: 2 }, // 3 al 6 de julio
  { fase: "Cuartos",       primerDia: 39, porDia: 2 }, // 9 y 10 de julio
  { fase: "Semifinal",     primerDia: 43, porDia: 1 }, // 13 y 14 de julio
  { fase: "Final",         primerDia: 51, porDia: 1 }, // 21 de julio
];

// --- Equipos y jugadores: desde MongoDB -----------------------------------------

// La consulta ya los devuelve ordenados (equipos por grupo y ranking; jugadores
// por equipo y dorsal), asi el generador no necesita reordenar nada.
const equipos = fixture.equipos
  .find({}, { nombre: 1, confederacion: 1, grupo: 1, ranking_fifa: 1 })
  .sort({ grupo: 1, ranking_fifa: 1 })
  .toArray();
const jugadores = fixture.jugadores
  .find({}, { nombre: 1, apellido: 1, posicion: 1, dorsal: 1, "equipo._id": 1 })
  .sort({ "equipo._id": 1, dorsal: 1 })
  .toArray();

verificar(equipos.length === 64, `MongoDB tiene ${equipos.length} equipos y se esperan 64.`);
verificar(jugadores.length >= 1000, `MongoDB tiene ${jugadores.length} jugadores (minimo 1.000).`);

const ranking = {};
const grupoDe = {};
const grupos = {};  // grupo -> ids de sus equipos, del mejor al peor ranking
const plantel = {}; // equipo -> jugadores por posicion, ordenados por dorsal
equipos.forEach((e) => {
  ranking[e._id] = e.ranking_fifa;
  grupoDe[e._id] = e.grupo;
  if (grupos[e.grupo] === undefined) grupos[e.grupo] = [];
  grupos[e.grupo].push(e._id);
  plantel[e._id] = { Arquero: [], Defensor: [], Mediocampista: [], Delantero: [] };
});
const letras = Object.keys(grupos); // A a P
letras.forEach((l) => verificar(grupos[l].length === 4, `el grupo ${l} tiene ${grupos[l].length} equipos.`));

jugadores.forEach((j) => {
  verificar(plantel[j.equipo._id] !== undefined, `el jugador ${j._id} referencia un equipo inexistente.`);
  plantel[j.equipo._id][j.posicion].push({ id: j._id, posicion: j.posicion });
});

// --- Simulacion de un partido ---------------------------------------------------

const FORMACION = [ // 1-4-3-3
  { posicion: "Arquero", cantidad: 1 },
  { posicion: "Defensor", cantidad: 4 },
  { posicion: "Mediocampista", cantidad: 3 },
  { posicion: "Delantero", cantidad: 3 },
];
const PESO_GOL = { Arquero: 0, Defensor: 1, Mediocampista: 3, Delantero: 6 };
const PESO_ASISTENCIA = { Arquero: 0, Defensor: 2, Mediocampista: 4, Delantero: 3 };
const PESO_TARJETA = { Arquero: 0.3, Defensor: 3, Mediocampista: 3, Delantero: 1 };
const ROLES_POR_TIPO = {
  Gol: ["autor", "autor,asistencia"],
  "Sustitución": ["sale,entra"],
  "Tarjeta Amarilla": ["amonestado"],
  "Tarjeta Roja": ["expulsado"],
};

// Titulares: en cada puesto, los de menor dorsal son los habituales y pesan mas.
function alinear(equipoId, azar) {
  const titulares = [];
  const banco = [];
  FORMACION.forEach(({ posicion, cantidad }) => {
    let candidatos = plantel[equipoId][posicion];
    for (let i = 0; i < cantidad; i++) {
      const opciones = candidatos.map((j, orden) => ({ jugador: j, peso: 1 / (orden + 1) }));
      const elegido = azar.ponderado(opciones, (o) => o.peso).jugador;
      candidatos = candidatos.filter((j) => j !== elegido);
      titulares.push(elegido);
    }
    candidatos.forEach((j) => banco.push(j));
  });
  return { titulares, banco };
}

// Devuelve alineados, eventos (en orden cronologico) y marcador. En eliminacion
// directa no hay empate: si los goles igualan, uno de los dos convierte en la
// prorroga (minuto 91 a 120).
function jugarPartido(partido, eliminacion) {
  const azar = crearAzar(partido.id);
  const eventos = [];
  const alineados = []; // { jugador, equipo, titular }
  const estado = {};    // jugador -> { entrada, salida, expulsion }

  const lados = [partido.local, partido.visitante].map((equipoId) => {
    const alineacion = alinear(equipoId, azar);
    alineacion.titulares.forEach((j) => {
      estado[j.id] = { entrada: 0, salida: null, expulsion: null };
      alineados.push({ jugador: j.id, equipo: equipoId, titular: true });
    });
    return { equipo: equipoId, jugadores: alineacion.titulares, banco: alineacion.banco };
  });

  const enCancha = (j, minuto) => {
    const e = estado[j.id];
    return (
      e !== undefined &&
      e.entrada <= minuto &&
      (e.salida === null || e.salida > minuto) &&
      (e.expulsion === null || e.expulsion > minuto)
    );
  };
  const disponibles = (lado, minuto) => lado.jugadores.filter((j) => enCancha(j, minuto));

  // 1. Sustituciones: entre 3 y 5 por equipo, en el segundo tiempo y en minutos
  //    crecientes. Sale un titular de campo; entra preferentemente alguien del
  //    mismo puesto.
  lados.forEach((lado) => {
    const cantidad = azar.entero(3, 5);
    let minuto = azar.entero(46, 60);
    for (let n = 0; n < cantidad && minuto <= 89; n++) {
      const salen = disponibles(lado, minuto).filter(
        (j) => j.posicion !== "Arquero" && estado[j.id].entrada === 0,
      );
      const entran = lado.banco.filter((j) => j.posicion !== "Arquero");
      const sale = salen[Math.floor(azar.rnd() * salen.length)];
      const entra = azar.ponderado(entran, (j) => (j.posicion === sale.posicion ? 4 : 1));
      estado[sale.id].salida = minuto;
      estado[entra.id] = { entrada: minuto, salida: null, expulsion: null };
      lado.banco = lado.banco.filter((j) => j !== entra);
      lado.jugadores.push(entra);
      alineados.push({ jugador: entra.id, equipo: lado.equipo, titular: false });
      eventos.push({
        tipo: "Sustitución",
        minuto,
        protagonistas: [
          { jugador: sale.id, rol: "sale" },
          { jugador: entra.id, rol: "entra" },
        ],
      });
      minuto += azar.entero(1, 8);
    }
  });

  // 2. Goles: seis ocasiones por equipo; cada una se convierte con una
  //    probabilidad que crece con la diferencia de ranking FIFA a favor.
  const goles = lados.map((lado, i) => {
    const rival = lados[1 - i];
    let probabilidad = 0.22 + (ranking[rival.equipo] - ranking[lado.equipo]) * 0.003;
    if (probabilidad < 0.08) probabilidad = 0.08;
    if (probabilidad > 0.4) probabilidad = 0.4;
    let cantidad = 0;
    for (let k = 0; k < 6; k++) {
      if (azar.rnd() < probabilidad) cantidad++;
    }
    return cantidad;
  });
  let prorroga = null; // indice del lado que convierte en la prorroga
  if (eliminacion && goles[0] === goles[1]) {
    const fuerza = lados.map((l) => 1 / ranking[l.equipo]);
    prorroga = azar.rnd() * (fuerza[0] + fuerza[1]) < fuerza[0] ? 0 : 1;
  }
  lados.forEach((lado, i) => {
    const minutos = [];
    for (let k = 0; k < goles[i]; k++) minutos.push(azar.entero(1, 90));
    if (prorroga === i) minutos.push(azar.entero(91, 120));
    minutos.forEach((minuto) => {
      const autor = azar.ponderado(disponibles(lado, minuto), (j) => PESO_GOL[j.posicion]);
      const protagonistas = [{ jugador: autor.id, rol: "autor" }];
      if (azar.rnd() < 0.7) {
        const companeros = disponibles(lado, minuto).filter(
          (j) => j.id !== autor.id && PESO_ASISTENCIA[j.posicion] > 0,
        );
        if (companeros.length > 0) {
          const asistente = azar.ponderado(companeros, (j) => PESO_ASISTENCIA[j.posicion]);
          protagonistas.push({ jugador: asistente.id, rol: "asistencia" });
        }
      }
      eventos.push({ tipo: "Gol", minuto, protagonistas });
    });
  });

  // 3. Tarjetas amarillas: entre 2 y 5 por partido, a lo sumo una por jugador.
  const amonestados = new Set();
  for (let k = azar.entero(2, 5); k > 0; k--) {
    const lado = lados[azar.entero(0, 1)];
    const minuto = azar.entero(1, 90);
    const candidatos = disponibles(lado, minuto).filter((j) => !amonestados.has(j.id));
    if (candidatos.length > 0) {
      const jugador = azar.ponderado(candidatos, (j) => PESO_TARJETA[j.posicion]);
      amonestados.add(jugador.id);
      eventos.push({ tipo: "Tarjeta Amarilla", minuto, protagonistas: [{ jugador: jugador.id, rol: "amonestado" }] });
    }
  }

  // 4. Tarjeta roja en uno de cada ocho partidos, aproximadamente. Solo a un
  //    jugador de campo que no sale reemplazado y sin ninguna accion posterior,
  //    para que la cronologia del partido sea coherente.
  if (azar.rnd() < 0.125) {
    const lado = lados[azar.entero(0, 1)];
    const minuto = azar.entero(60, 90);
    const ultimaAccion = (id) => {
      let ultima = 0;
      eventos.forEach((e) => {
        const participa = e.protagonistas.filter((x) => x.jugador === id).length > 0;
        if (participa && e.minuto > ultima) ultima = e.minuto;
      });
      return ultima;
    };
    const candidatos = disponibles(lado, minuto).filter(
      (j) => j.posicion !== "Arquero" && estado[j.id].salida === null && ultimaAccion(j.id) < minuto,
    );
    if (candidatos.length > 0) {
      const jugador = azar.ponderado(candidatos, (j) => PESO_TARJETA[j.posicion]);
      estado[jugador.id].expulsion = minuto;
      eventos.push({ tipo: "Tarjeta Roja", minuto, protagonistas: [{ jugador: jugador.id, rol: "expulsado" }] });
    }
  }

  // Orden cronologico: se recorren los minutos del 1 al 120.
  const cronologia = [];
  for (let m = 1; m <= 120; m++) {
    eventos.filter((e) => e.minuto === m).forEach((e) => cronologia.push(e));
  }
  const marcador = goles.map((g, i) => g + (prorroga === i ? 1 : 0));
  return { alineados, eventos: cronologia, marcador };
}

// --- Fase de grupos: 16 grupos x 6 partidos = 96 --------------------------------

// Todos contra todos en tres jornadas. local y visitante son posiciones dentro del
// grupo ordenado por ranking: 1-4 y 2-3; 1-3 y 4-2; 1-2 y 3-4.
const CRUCES_GRUPO = [
  { jornada: 0, local: 0, visitante: 3 },
  { jornada: 0, local: 1, visitante: 2 },
  { jornada: 1, local: 0, visitante: 2 },
  { jornada: 1, local: 3, visitante: 1 },
  { jornada: 2, local: 0, visitante: 1 },
  { jornada: 2, local: 2, visitante: 3 },
];

function crearPartidoGrupo(letra, k) {
  const cruce = CRUCES_GRUPO[k];
  return {
    fase: "Grupos",
    grupo: letra,
    local: grupos[letra][cruce.local],
    visitante: grupos[letra][cruce.visitante],
  };
}

function esDelCentenario(p) {
  return CENTENARIO.filter((c) => c.equipo === p.local || c.equipo === p.visitante).length > 0;
}

// Los partidos se arman directamente en orden de fecha, que es el orden de sus id.
const partidos = [];

// 1. Partidos del centenario (8 al 10 de junio): el anfitrion juega de local.
CENTENARIO.forEach((c) => {
  letras.forEach((letra) => {
    [0, 1].forEach((k) => {
      const p = crearPartidoGrupo(letra, k);
      if (p.local !== c.equipo && p.visitante !== c.equipo) return;
      p.visitante = p.local === c.equipo ? p.visitante : p.local;
      p.local = c.equipo;
      p.sede = c.sede;
      p.fecha = fecha(c.dia);
      partidos.push(p);
    });
  });
});

// 2. El resto de la fase de grupos. Cada grupo tiene dos sedes y los dos partidos
//    de cada jornada se reparten entre ellas.
[0, 1, 2].forEach((jornada) => {
  letras.forEach((letra, g) => {
    const primera = SEDES_EUROPA_AFRICA[(2 * g) % SEDES_EUROPA_AFRICA.length];
    const segunda = SEDES_EUROPA_AFRICA[(2 * g + 1) % SEDES_EUROPA_AFRICA.length];
    CRUCES_GRUPO.forEach((cruce, k) => {
      if (cruce.jornada !== jornada) return;
      const p = crearPartidoGrupo(letra, k);
      if (jornada === 0 && esDelCentenario(p)) return; // ya agregado en el paso 1
      p.sede = k % 2 === 0 ? primera : segunda;
      p.fecha = fecha(diaDeGrupo(jornada, g));
      partidos.push(p);
    });
  });
});

verificar(partidos.length === 96, `la fase de grupos tiene ${partidos.length} partidos y se esperan 96.`);

let numeroPartido = 0;
function nuevoIdPartido() {
  numeroPartido++;
  return `P-${String(numeroPartido).padStart(3, "0")}`;
}

const tabla = {}; // equipo -> { pts, gf, gc }
equipos.forEach((e) => (tabla[e._id] = { pts: 0, gf: 0, gc: 0 }));

partidos.forEach((p) => {
  p.id = nuevoIdPartido();
  p.resultado = jugarPartido(p, false);
  const gl = p.resultado.marcador[0];
  const gv = p.resultado.marcador[1];
  tabla[p.local].gf += gl;
  tabla[p.local].gc += gv;
  tabla[p.visitante].gf += gv;
  tabla[p.visitante].gc += gl;
  tabla[p.local].pts += gl > gv ? 3 : gl === gv ? 1 : 0;
  tabla[p.visitante].pts += gv > gl ? 3 : gl === gv ? 1 : 0;
});

// Verdadero si el equipo a queda por encima de b: puntos, diferencia de gol,
// goles a favor y, por ultimo, ranking FIFA.
function quedaArriba(a, b) {
  const ta = tabla[a];
  const tb = tabla[b];
  if (ta.pts !== tb.pts) return ta.pts > tb.pts;
  const difA = ta.gf - ta.gc;
  const difB = tb.gf - tb.gc;
  if (difA !== difB) return difA > difB;
  if (ta.gf !== tb.gf) return ta.gf > tb.gf;
  return ranking[a] < ranking[b];
}

function mejorDe(lista) {
  let mejor = lista[0];
  lista.forEach((x) => {
    if (quedaArriba(x, mejor)) mejor = x;
  });
  return mejor;
}

// Clasifican los dos primeros de cada grupo.
const clasificados = {}; // grupo -> [primero, segundo]
letras.forEach((l) => {
  const primero = mejorDe(grupos[l]);
  const segundo = mejorDe(grupos[l].filter((x) => x !== primero));
  clasificados[l] = [primero, segundo];
});

// --- Eliminacion directa: 16 + 8 + 4 + 2 + 1 = 31 ------------------------------

// Dieciseisavos: el primero de cada grupo contra el segundo del grupo vecino
// (A-B, C-D, ...). Las dos mitades del cuadro solo se cruzan en la final, asi que
// dos equipos del mismo grupo no pueden volver a enfrentarse antes.
let cruces = [];
for (let k = 0; k < 8; k++) {
  cruces.push({ a: clasificados[letras[2 * k]][0], b: clasificados[letras[2 * k + 1]][1] });
}
for (let k = 0; k < 8; k++) {
  cruces.push({ a: clasificados[letras[2 * k + 1]][0], b: clasificados[letras[2 * k]][1] });
}

RONDAS.forEach((ronda) => {
  const ganadores = [];
  cruces.forEach((cruce, i) => {
    // Local: el de mejor ranking FIFA.
    const local = ranking[cruce.a] <= ranking[cruce.b] ? cruce.a : cruce.b;
    const visitante = local === cruce.a ? cruce.b : cruce.a;
    const p = {
      id: nuevoIdPartido(),
      fase: ronda.fase,
      grupo: null,
      fecha: fecha(ronda.primerDia + Math.floor(i / ronda.porDia)),
      sede: SEDES_ELIMINACION[ronda.fase][i],
      local,
      visitante,
    };
    p.resultado = jugarPartido(p, true);
    partidos.push(p);
    ganadores.push(p.resultado.marcador[0] > p.resultado.marcador[1] ? local : visitante);
  });
  cruces = [];
  for (let i = 0; i + 1 < ganadores.length; i += 2) cruces.push({ a: ganadores[i], b: ganadores[i + 1] });
});

// Ids de eventos: correlativos en el orden de los partidos y, dentro de cada uno,
// en orden cronologico.
let numeroEvento = 0;
const eventos = [];
partidos.forEach((p) => {
  p.resultado.eventos.forEach((e) => {
    numeroEvento++;
    e.id = `E-${String(numeroEvento).padStart(4, "0")}`;
    e.partido = p.id;
    eventos.push(e);
  });
});

// --- Controles de coherencia ----------------------------------------------------

verificar(partidos.length === 127, `se generaron ${partidos.length} partidos y se esperan 127.`);
verificar(numeroEvento <= 9999, "los eventos no entran en el formato E-XXXX.");

const idsPartido = new Set();
const sedeYFecha = new Set();
const partidosPorEquipo = {};
equipos.forEach((e) => (partidosPorEquipo[e._id] = 0));

partidos.forEach((p) => {
  verificar(!idsPartido.has(p.id), `id de partido repetido: ${p.id}.`);
  idsPartido.add(p.id);
  const clave = `${p.sede} ${p.fecha}`;
  verificar(!sedeYFecha.has(clave), `${p.sede} recibe dos partidos el ${p.fecha}.`);
  sedeYFecha.add(clave);
  verificar(p.local !== p.visitante, `${p.id}: un equipo contra si mismo.`);
  partidosPorEquipo[p.local]++;
  partidosPorEquipo[p.visitante]++;
  if (p.fase === "Grupos") {
    verificar(grupoDe[p.local] === p.grupo && grupoDe[p.visitante] === p.grupo, `${p.id}: equipos fuera de su grupo.`);
  }
  const alineados = new Set();
  p.resultado.alineados.forEach((a) => {
    verificar(!alineados.has(a.jugador), `${p.id}: ${a.jugador} alineado dos veces.`);
    alineados.add(a.jugador);
  });
  [p.local, p.visitante].forEach((equipoId) => {
    const delEquipo = p.resultado.alineados.filter((a) => a.equipo === equipoId);
    verificar(delEquipo.filter((a) => a.titular).length === 11, `${p.id}: ${equipoId} no tiene 11 titulares.`);
    verificar(delEquipo.filter((a) => !a.titular).length <= 5, `${p.id}: ${equipoId} hizo mas de 5 cambios.`);
  });
  p.resultado.eventos.forEach((e) => {
    const roles = e.protagonistas.map((x) => x.rol).join(",");
    verificar(ROLES_POR_TIPO[e.tipo].includes(roles), `${e.id}: protagonistas invalidos (${roles}).`);
    e.protagonistas.forEach((x) =>
      verificar(alineados.has(x.jugador), `${e.id}: ${x.jugador} no jugo el partido ${p.id}.`),
    );
  });
});

equipos.forEach((e) =>
  verificar(
    partidosPorEquipo[e._id] >= 3 && partidosPorEquipo[e._id] <= 8,
    `${e._id} juega ${partidosPorEquipo[e._id]} partidos (se esperan entre 3 y 8).`,
  ),
);

// --- Salida ---------------------------------------------------------------------

// Ningun dato lleva comas ni comillas, asi que cada valor se escribe tal cual. Si
// alguno las tuviera, el CSV quedaria mal armado: se controla en lugar de suponerlo.
function linea(valores) {
  return valores
    .map((v) => {
      if (v === null) return ""; // grupo vacio en eliminacion directa
      const texto = String(v);
      verificar(!texto.includes(",") && !texto.includes('"'), `el valor "${texto}" tiene comas o comillas.`);
      return texto;
    })
    .join(",");
}

const ARCHIVOS = {
  equipos: () => {
    const filas = [["id", "nombre", "confederacion", "grupo"]];
    equipos.forEach((e) => filas.push([e._id, e.nombre, e.confederacion, e.grupo]));
    return filas;
  },
  jugadores: () => {
    const filas = [["id", "nombre", "apellido", "posicion", "equipo_id"]];
    jugadores.forEach((j) => filas.push([j._id, j.nombre, j.apellido, j.posicion, j.equipo._id]));
    return filas;
  },
  sedes: () => {
    const filas = [["id", "nombre", "ciudad", "pais"]];
    SEDES.forEach((s) => filas.push([s.id, s.nombre, s.ciudad, s.pais]));
    return filas;
  },
  partidos: () => {
    const filas = [["id", "fase", "grupo", "fecha", "sede_id"]];
    partidos.forEach((p) => filas.push([p.id, p.fase, p.grupo, p.fecha, p.sede]));
    return filas;
  },
  participaciones: () => {
    const filas = [["partido_id", "equipo_id", "condicion"]];
    partidos.forEach((p) => {
      filas.push([p.id, p.local, "Local"]);
      filas.push([p.id, p.visitante, "Visitante"]);
    });
    return filas;
  },
  alineaciones: () => {
    const filas = [["partido_id", "jugador_id", "titular"]];
    partidos.forEach((p) => p.resultado.alineados.forEach((a) => filas.push([p.id, a.jugador, a.titular])));
    return filas;
  },
  eventos: () => {
    const filas = [["id", "partido_id", "tipo", "minuto"]];
    eventos.forEach((e) => filas.push([e.id, e.partido, e.tipo, e.minuto]));
    return filas;
  },
  protagonistas: () => {
    const filas = [["evento_id", "jugador_id", "rol"]];
    eventos.forEach((e) => e.protagonistas.forEach((x) => filas.push([e.id, x.jugador, x.rol])));
    return filas;
  },
};

if (ARCHIVO === "resumen") {
  Object.keys(ARCHIVOS).forEach((nombre) =>
    print(`  import/${nombre}.csv: ${ARCHIVOS[nombre]().length - 1} filas`),
  );
} else {
  verificar(ARCHIVOS[ARCHIVO] !== undefined, `ARCHIVO desconocido: ${ARCHIVO}.`);
  ARCHIVOS[ARCHIVO]().forEach((fila) => print(linea(fila)));
}
