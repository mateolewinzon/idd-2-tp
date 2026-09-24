# Hito 4 — Módulo Documental de Equipos y Jugadores (MongoDB)

Plataforma del Fixture del Mundial 2030 — Ingeniería de Datos II.

Este directorio implementa el módulo documental de **Equipos** y **Jugadores** en
MongoDB, según las decisiones tecnológicas del Hito 2 y los condicionantes de
arquitectura distribuida del Hito 3.

Las decisiones de modelado y su vínculo con los hitos previos están en
[`Grupo_11_Hito_4_Decisiones_Documentales_Fixture2030.md`](./Grupo_11_Hito_4_Decisiones_Documentales_Fixture2030.md).

---

## 1. Requisitos

- **Docker Desktop** (o una instalación equivalente de Docker con Compose v2).
- Nada más. No hace falta instalar MongoDB, `mongosh`, Node ni npm: todo corre
  dentro del contenedor.
- El puerto **27017** debe estar libre. Si ya tenés un MongoDB local corriendo,
  detenelo o cambiá el mapeo de puertos en `docker-compose.yaml`.

Probado en macOS (Apple Silicon) con Docker 27.4 y MongoDB 7.0.40.

---

## 2. Puesta en marcha

Tres comandos desde este directorio:

```bash
./scripts/levantar.sh      # levanta MongoDB y espera a que responda
./scripts/cargar.sh        # crea colecciones, validaciones, índices y carga los datos
./scripts/verificar.sh     # comprueba volumen e integridad (RNF2 y RNF3)
./scripts/consultar.sh     # ejecuta las operaciones y consultas 1 a 7 (Punto 4)
./scripts/rendimiento.sh   # ejecuta el análisis explain() e indexación (Punto 5)
```

Salida esperada del último paso de verificación:

```
  RESULTADO: todas las verificaciones pasaron.
  64 equipos | 1664 jugadores | 0 huerfanos
```

Y para dejar registrada la evidencia del ambiente: disponibilidad de MongoDB y
persistencia de los datos ante un reinicio.

```bash
./scripts/evidencia-ambiente.sh     # RF1 y RF2 — reinicia el contenedor a propósito
```

### Ver los datos

Con MongoDB Compass o cualquier cliente, conectando a:

```
mongodb://localhost:27017/fixture2030
```

O directamente desde el contenedor:

```bash
docker compose exec mongo mongosh fixture2030
```

---

## 3. Ciclo de vida del ambiente

El volumen `fixture2030_data` guarda los datos fuera del contenedor. Esto es lo
que hace cada operación:

| Acción                              | Comando                  | ¿Se pierden los datos?        |
| ----------------------------------- | ------------------------ | ----------------------------- |
| Levantar                            | `./scripts/levantar.sh`  | —                             |
| Detener (conservando el contenedor) | `docker compose stop`    | **No**                        |
| Reiniciar                           | `docker compose restart` | **No**                        |
| Volver a arrancar tras detener      | `docker compose start`   | **No**                        |
| Eliminar el contenedor              | `docker compose down`    | **No** — el volumen sobrevive |
| Eliminar contenedor **y volumen**   | `docker compose down -v` | **Sí, todo**                  |
| Reset completo asistido             | `./scripts/reset.sh`     | **Sí** (pide confirmación)    |

El único comando destructivo es `down -v`. `./scripts/reset.sh` lo envuelve
pidiendo confirmación explícita, para que no se ejecute por accidente.

### Volver a cargar los datos

`./scripts/cargar.sh` se puede ejecutar **las veces que haga falta**. La carga es
idempotente: usa `bulkWrite` con `upsert` sobre identificadores de negocio, sin
borrar nada previamente. En la segunda corrida y sucesivas informa:

```
  Documentos encontrados (matched):  1664
  Documentos insertados (upserted):  0
  Documentos modificados (modified): 0

  -> Sin cambios: la base ya estaba en el estado esperado.
```

Para reconstruir el ambiente desde cero:

```bash
./scripts/reset.sh
./scripts/levantar.sh
./scripts/cargar.sh
```

El resultado es **idéntico** al anterior: el generador de jugadores es
determinista (ver sección 5).

---

## 4. Estructura de archivos

```
.
├── docker-compose.yaml              Ambiente MongoDB 7 con volumen persistente
├── README.md                        Este archivo
├── Grupo_11_Hito_4_Decisiones_Documentales_Fixture2030.md
│
├── datos/
│   └── equipos.js                   Dataset fijo: las 64 selecciones
│
├── mongo/                           Scripts ejecutados dentro del contenedor
│   ├── 01-setup-colecciones.js      Colecciones, $jsonSchema e índices
│   ├── 02-carga-equipos.js          Carga idempotente de los 64 equipos
│   ├── 03-carga-jugadores.js        Generación y carga de 1.664 jugadores
│   ├── 04-verificar-integridad.js   Verificación RNF2 y RNF3 (solo lectura)
│   ├── 05-operaciones-consultas.js  Operaciones 1 a 7 en BSON/JSON crudo (Punto 4)
│   └── 06-analisis-rendimiento.js   Diagnóstico explain e indexación (Punto 5)
│
├── scripts/                         Envoltorios ejecutables desde el host
│   ├── levantar.sh
│   ├── cargar.sh
│   ├── verificar.sh
│   ├── consultar.sh                 Ejecuta Punto 4 y vuelca a evidencia/operaciones.txt
│   ├── rendimiento.sh               Ejecuta Punto 5 y vuelca a evidencia/rendimiento.txt
│   ├── evidencia-ambiente.sh
│   └── reset.sh
│
└── evidencia/                       Salidas de consola de las corridas
    ├── ambiente.txt
    ├── carga.txt
    ├── verificacion.txt
    ├── operaciones.txt              Salida BSON/JSON de las operaciones 1 a 7 (Punto 4)
    └── rendimiento.txt              Salida explain() antes y después del índice (Punto 5)
```

Los scripts de `mongo/` se montan en el contenedor como `/scripts` (solo
lectura) y `datos/` como `/datos`.

---

## 5. Datos cargados

| Colección   | Documentos | Origen                                         |
| ----------- | ---------- | ---------------------------------------------- |
| `equipos`   | 64         | Dataset fijo, versionado en `datos/equipos.js` |
| `jugadores` | 1.664      | Generados: 26 por selección                    |

**Equipos.** Las 48 selecciones del Mundial 2026 (heredadas del seed original del
grupo, grupos A a L) más 16 selecciones que completan las 64 del escenario
(grupos M a P), repartidas respetando cupos plausibles por confederación:
UEFA 22, CAF 13, AFC 11, CONMEBOL 9, CONCACAF 7, OFC 2.

**Jugadores.** Datos sintéticos, explícitamente habilitados por RNF8. 26 por
plantel es el tamaño que la FIFA permite actualmente; 64 × 26 = **1.664**, que
supera tanto el mínimo de 1.000 de RF5 como la cifra de "más de 1.500 jugadores"
del escenario del Hito 4.

**Los datos sintéticos no son aleatorios.** El generador usa un PRNG
(`mulberry32`) sembrado con un hash del código FIFA del equipo. Volver a
generarlos produce exactamente los mismos 1.664 documentos, con los mismos
nombres, dorsales y fechas de nacimiento. Sin esto la carga no sería
reproducible: cada ejecución crearía personas distintas y el `upsert` modificaría
documentos en lugar de no hacer nada, rompiendo RF8.

---

## 6. Evidencia

El directorio `evidencia/` contiene la salida de consola de las corridas.
Se regenera automáticamente cada vez que se ejecuta el script correspondiente.

- **`ambiente.txt`** — estado del contenedor, volumen persistente, versión de
  MongoDB respondiendo a `ping`, y el conteo de documentos antes y después de
  reiniciar el contenedor (evidencia de RF2).
- **`carga.txt`** — setup, conteos de la carga y reparto por confederación y
  posición. Se **acumula** entre corridas: contiene la primera carga (64 y 1.664
  insertados) y las repeticiones (0 insertados, 0 modificados), que juntas son la
  evidencia de RF8.
- **`verificacion.txt`** — las 13 verificaciones de RNF2 y RNF3: volumen,
  identificadores duplicados, jugadores huérfanos, equipos sin plantel, snapshot
  desincronizado, campos críticos ausentes, coherencia de planteles, validadores
  e índices activos.
- **`operaciones.txt`** — documentos en formato JSON/BSON crudo devueltos por
  MongoDB para cada una de las 7 operaciones requeridas del Punto 4 (inserción,
  recuperación por ID, filtrada, proyección, paginación, actualización atómica
  y pipeline de agregación consolidada).
- **`rendimiento.txt`** — resultado completo de `.explain("executionStats")` para
  el Punto 5 demostrando la optimización de la consulta crítica: evidencia el paso
  de un escaneo total con ordenamiento en RAM (`COLLSCAN` + `SORT`, examinando 1.664
  documentos) a una búsqueda indexada eficiente (`IXSCAN` + `FETCH`, examinando 35
  claves y 35 documentos) tras aplicar `createIndex({ club: 1, fecha_nacimiento: 1 })`.

---

## 7. Limitaciones conocidas

**Sin autenticación.** El ambiente local corre sin usuario ni contraseña. Es
deliberado: prioriza que cualquiera pueda levantarlo sin configurar nada
(RNF1, RNF7). En producción el módulo requeriría autenticación SCRAM para los
clientes y, al operar como conjunto de réplicas, un keyfile o certificados x.509
para la autenticación interna entre miembros.

**Nodo único.** El ambiente levanta un solo `mongod`, no el conjunto de réplicas
que el Hito 3 definió para este subsistema. Ningún requisito del Hito 4 pide
replicación, y montarla localmente agregaría tres contenedores y una dependencia
de orden de arranque sin aportar evidencia de nada que este hito evalúe. La
decisión de replicación se documenta y justifica en el documento de decisiones;
no se reproduce en el entorno de desarrollo.

**Sin integridad referencial declarativa.** MongoDB no tiene claves foráneas:
`$jsonSchema` valida cada documento por separado y no puede comprobar que
`jugadores.equipo._id` apunte a un equipo existente. Se compensa en dos frentes:
la carga _previene_ el problema generando los jugadores a partir de los equipos
ya persistidos, y `04-verificar-integridad.js` lo _detecta_ después.

**Snapshot desnormalizado.** Los jugadores guardan una copia de
`{nombre, confederación}` de su equipo. Si un equipo se renombrara sin propagar
el cambio, esas copias quedarían desfasadas. La verificación de integridad
incluye un control específico para detectarlo. La actualización propagada
corresponde a las operaciones del ítem 4, fuera del alcance de esta entrega.

**Datos sintéticos.** Los nombres, clubes y datos físicos de los jugadores son
generados, no reales. Los equipos, confederaciones, rankings y directores
técnicos sí corresponden a datos reales o verosímiles, pero la clasificación al
Mundial 2030 todavía no ocurrió: los 64 participantes son una hipótesis de
trabajo.
