# Análisis Hito 9 — InterSystems IRIS — Fixture 2030

## §0 Decisiones tomadas

1. **Ubicación y alcance de esta fase.** El módulo se alojará en `fixture2030-InterSystems-iris/`. Fase 0 crea solamente el esqueleto `docs/`, `scripts/` y `evidencia/`; no agrega README final, scripts funcionales ni clases.
2. **Tecnología y persistencia.** El motor del módulo es InterSystems IRIS Community en Docker Compose, con Durable %SYS persistido en `~/docker/data/iris`, según el enunciado Hito 9. El compose publica localmente los puertos 1972 y 52773 y monta `scripts/` en solo lectura como muestra la Clase 10. Los archivos de datos de IRIS quedan fuera del repositorio.
3. **Frontera del dominio.** Se preservan las asignaciones previas: MongoDB para Equipos, Jugadores, Alineaciones y Usuarios, y Neo4j para Partidos y Eventos (la matriz de Hito 2 pone Partidos en MongoDB, pero Hito 3 los consolida junto con Eventos en Neo4j). InfluxDB conserva exclusivamente observaciones temporales y no será fuente de verdad de equipos, jugadores, partidos ni eventos. El rol de IRIS debe limitarse a cumplir el módulo didáctico de Hito 9 sin reasignar las fuentes de verdad aprobadas.
4. **Entidades autorizadas.** El modelo previo documenta Partido, Evento, Jugador, Equipo y Sede; Hito 4 mantiene director técnico como atributo de Equipo. La usuaria autorizó explícitamente Árbitro como la segunda subclase de Persona que requiere RF4. No se suman otras entidades nuevas.
5. **Jerarquía y agregado elegidos.** `Persona` es la clase persistente base de `Jugador` y `Árbitro`. `Partido` y `Evento` forman la relación padre-hijo. Para mantener las fuentes previas, los objetos de Jugador, Partido y Evento que se creen en IRIS se tratarán como instancias de demostración de Hito 9, no como autoridad ni como migración: MongoDB conserva Jugadores y Neo4j conserva Partidos/Eventos.
6. **Trazabilidad.** Se seguirá la estructura del análisis de Hito 8: decisiones, matriz RF/RNF a archivo, riesgos y plan por fases. Se tomará el nivel de detalle y las guías de ejecución de los módulos hermanos como referencia de presentación; las instrucciones técnicas de IRIS se limitarán a `contexto/Clase_10...html`.

## Coherencia RF/RNF → archivo (destino previsto)

| Requisito | Archivo(s) previsto(s) |
| --- | --- |
| RF1, RNF1 | `docker-compose.yml`, `.gitignore`, `README.md`, `evidencia/ambiente.txt` |
| RF2, RF4, RF5, RF9; RNF2 | `scripts/Fixture.*.cls`, `docs/modelo_de_objetos.md`, evidencia de compilación/validación generada por `scripts/demo_objetos.sh` |
| RF3, RNF3 | `scripts/Fixture.*.cls`, `docs/matriz_de_integridad.md`, evidencia de navegación de la relación |
| RF6 | `scripts/demo_objetos.sh` (ejecución de la carga del árbol), evidencia de guardado único del árbol de objetos |
| RF7 | `scripts/demo_objetos.sh`, evidencia de navegación desde objetos |
| RF8 | `scripts/Fixture.Demo.cls`, evidencia de proyección SQL desde `$SYSTEM.SQL.Execute` |
| RNF4 | Fuentes `.cls` y comandos invocables desde Terminal IRIS, documentados en `README.md` |
| RNF5 | Estructura preparada en este repositorio; historial remoto y acceso del docente requieren commit/publicación, acciones fuera de alcance por instrucción explícita de no commitear ni pushear |
| PDF §8: diagrama y campos obligatorios | `docs/modelo_de_objetos.md` |
| PDF §8: reglas de borrado/integridad | `docs/matriz_de_integridad.md` |
| PDF §8: operativa y evidencia | `README.md`, `scripts/`, `evidencia/` |

## Riesgos y decisiones pendientes

- **Fuente de verdad y representación de Hito 9:** las instancias de Jugador, Partido y Evento en IRIS son demostrativas; no se implementará sincronización entre motores ni se las usará como fuentes autorizadas.
- **Árbitro:** se incorpora al modelo exclusivamente por la autorización explícita de la usuaria para satisfacer RF4. No se deriva esa decisión de los hitos anteriores.
- **Brechas cubiertas con documentación oficial:** Clase 10 enseña `$system.OBJ.Load` para una clase, pero no la carga/compilación conjunta de un directorio con clases relacionadas; el script usa `$system.OBJ.Import` para compilar todas las `.cls` juntas. Se buscó en Clase 10 cómo ejecutar SQL desde ObjectScript/Terminal y correr `.sql`; se encontró el ejemplo SELECT, pero no el mecanismo. La demo usa `$SYSTEM.SQL.Execute()`. Ambos usos llevan `encontrado en documentación oficial` en el código y en la documentación de uso.
- **Retención de datos local:** Durable %SYS debe persistir en `~/docker/data/iris`; no incluir el directorio ni credenciales en Git.
- **Integridad del agregado:** demostrar si los hijos se eliminan con su padre y que un único guardado persiste el objeto alcanzable sin estados parciales; no afirmar atomicidad hasta tener salida verificable.

## Plan por fases

- **Fase 0 — análisis y esqueleto:** verificar estado, preparar esta matriz, crear directorios vacíos y revisar que no haya cambios ajenos. Sin documentación final ni scripts.
- **Fase 1 — reconciliación del dominio:** completada con `Hito1.md`, `Hito2.md`, `Hito3.md` y los módulos Hito 4/5/8. La jerarquía es Persona→Jugador/Árbitro; el agregado es Partido→Evento; se preservan las fuentes de verdad.
- **Fase 2 — diseño documentado:** diagrama y matriz redactados; revisar trazabilidad final de todos los RF/RNF.
- **Fase 3 — servicio y fuentes:** Compose y fuentes `.cls` creadas; compilación verificada en IRIS.
- **Fase 4 — demostraciones:** guardado de árbol, navegación, validación, propiedad requerida, SQL y cascada ejecutadas; salida conservada en evidencia.
- **Fase 5 — revisión:** despliegue, persistencia tras reinicio, compilación, integridad, documentación y evidencia revisados. La publicación GitHub, el historial de commits y el acceso del docente permanecen pendientes por la instrucción explícita de no commitear ni pushear.

## Verificación inicial (tras `git pull`)

- Rama: `main`, sincronizada con `origin/main` en `9534f90`.
- Estado preexistente conservado: `fixture2030-cassandra.zip` y `fixture2030-redis.zip` permanecen sin seguimiento.
- Los directorios `fixture2030-influxdb/` y `fixture2030-neo4j/` y sus documentos ya están disponibles tras el pull.
- Se leyeron `Hito1.md`, `Hito2.md` y `Hito3.md`; la matriz base asigna MongoDB a equipos/jugadores/alineaciones/usuarios y Neo4j a eventos, mientras Hito 3 consolida partidos y eventos en Neo4j.
- RF4 se reconcilió con autorización explícita de la usuaria para incorporar `Árbitro`; el diseño de `Persona → Jugador/Árbitro` y `Partido → Evento` queda registrado en `docs/modelo_de_objetos.md`.
- No existía `fixture2030-InterSystems-iris/`; se creó en esta fase con `docs/`, `scripts/` y `evidencia/`.
- El ambiente incluye `docker-compose.yml` y `.gitignore`; `docker compose config` resolvió la configuración y el contenedor local se levantó para compilar y demostrar el modelo.
- La carga de clases y la demostración se ejecutaron sin errores de compilación; se verificó guardado, navegación bidireccional, SQL, cascada y rechazo de propiedades/eventos inválidos. No se hizo commit, push ni cambio de rama.
